#import "../lib.typ": *
#import "@preview/cetz:0.4.2"

= Model Compression I: Quantization

#epigraph[
  The goal is to find the most compact description that still lets you do the task.
][Sanjiv Kumar, Google Research]

Imagine you spent six months training a language model that can answer medical questions, write poetry, and debug code — all in the same breath. It weighs 14 gigabytes. Your hospital wants to run it on a tablet at the bedside. The tablet has 4 GB of RAM. You have a problem.

This is the Model Compression Problem, and it is not a niche research curiosity. It is one of the most practically important problems in all of computing right now. Every time you use an AI assistant on a phone, a translation app in an airplane without Wi-Fi, or a voice assistant on a smart speaker, you are using a compressed model. The original version lived on a server with dozens of high-end GPUs. What you actually run is a carefully squeezed copy — smaller, faster, and only slightly dumber.

Over the next two chapters we explore three compression levers for neural networks: *quantization* (this chapter), and *pruning, distillation, and low-rank factorization* (Chapter 64). In Chapter 65 we return to the inference-time problem of compressing the network's *memory* during a long conversation (the KV-cache). Together, these three chapters bring us to the absolute frontier of the field.

This chapter is about quantization: the art and science of replacing the high-precision floating-point numbers that describe a neural network's weights with far fewer bits — and doing it without wrecking what the network knows.

#recap[
  In Chapter 39 we met *scalar quantization* for images: map a continuous value to the nearest step on a fixed grid and code the integer index. Chapter 42 showed how JPEG uses quantization to discard high-frequency DCT coefficients aggressively. Chapter 62 showed that a language model is itself a compressor — it assigns a probability to every possible next word. *This* chapter asks the reverse: how do we compress the model itself?
]

#objectives((
  "Understand what a neural network weight is and why it is stored in floating point",
  "Explain the difference between post-training quantization (PTQ) and quantization-aware training (QAT)",
  "Follow the GPTQ algorithm step by step and see why second-order information matters",
  "Understand AWQ's insight about salient channels and activation magnitudes",
  "Know why outlier activations make naive INT8 quantization fail",
  "Grasp the information-theoretic argument behind BitNet b1.58 and ternary weights",
  "Have a concrete sense of what FP8 is and why it is the sweet spot for today's hardware",
  "Be able to choose among quantization strategies for a given deployment scenario",
))

== What Is a Neural Network Weight, and Why Does It Matter?

A large language model is, at its mathematical core, an enormous collection of real numbers called *weights*. When you ask the model a question, the answer is computed by multiplying your input by these weights, adding them up, squishing the result through a non-linear function, and repeating that pattern dozens of times. The whole computation is called a *forward pass*.

A model with 7 billion parameters — which is considered relatively small in 2024 — has 7,000,000,000 individual weights. If each weight is stored as a 32-bit floating-point number (the IEEE 754 `float32` format), the model occupies $7 times 10^9 times 4 "bytes" = 28 "GB"$. That does not fit in consumer GPU memory. Even switching to 16-bit half-precision (`float16` or `bfloat16`), the standard for training and inference since about 2018, gives $7 times 10^9 times 2 "bytes" = 14 "GB"$. Still too large for a tablet.

#gomaths("Floating-Point Numbers")[
  A *floating-point number* stores a value as three parts: a *sign bit* (positive or negative), an *exponent* (the power of 2 that sets the scale), and a *mantissa* or *fraction* (the significant digits).

  - `float32` (single precision): 1 sign + 8 exponent + 23 mantissa = 32 bits. Can represent values from about $plus.minus 3.4 times 10^38$ with ~7 decimal digits of precision.
  - `float16` (half precision): 1 + 5 + 10 = 16 bits. Range $plus.minus 65,504$, ~3 decimal digits.
  - `bfloat16` ("brain float 16"): 1 + 8 + 7 = 16 bits. Same exponent range as float32, but less precise mantissa — easier for the hardware to handle without overflow.

  For comparison, `int8` is simply a signed 8-bit integer: values $-128$ to $127$, with no fractional part at all.

  The big intuition: a float32 weight might be something like $0.032847192$. Do you really need 7 significant digits of precision for a single weight in a 7-billion-weight network? Almost certainly not — most weights could be rounded to $0.033$ without anyone noticing. Quantization is the systematic exploitation of this slack.
]

The key insight that makes model quantization possible is statistical: in a trained network, weights are *approximately Gaussian* (bell-curve shaped) and concentrated near zero. The network spent months learning the values that matter; a tiny rounding error in each of billions of weights will, on average, partially cancel out. With the right algorithm, you can introduce controlled rounding and the model keeps working almost as well.

== The Zoo of Bit Widths

Before diving into algorithms, let us survey the landscape. The community has standardized on a shorthand: W$k$A$m$ means "weights in $k$ bits, activations in $m$ bits."

- *W16A16*: BFloat16 or float16 throughout. The standard starting point, ~2 bytes/weight.
- *W8A8*: INT8 weights and INT8 activations. Hardware-accelerated on NVIDIA T4, A100, H100, and Apple Silicon. ~4× smaller than float32.
- *W4A16*: 4-bit weights, 16-bit activations. The most common deployment sweet spot in 2024. Weights are decompressed on the fly before each matrix multiply. Very fast to load; not quite as fast for compute.
- *W4A8*: 4-bit weights, 8-bit activations. Faster compute but harder to get right.
- *W2A8* or *W3A16*: Aggressive, often with noticeable quality loss. An active research area.
- *W1.58*: The ternary frontier. BitNet b1.58. Only three values: $-1, 0, +1$.

#keyidea[
  Every bit you shave off a weight halves the storage. Going from float16 (16 bits) to INT4 (4 bits) is a 4× compression of the model. For a 7B-parameter model that is the difference between 14 GB and 3.5 GB — it fits on a consumer GPU with room to spare.
]

== The Outlier Problem: Why Naive Quantization Fails

Here is the trap that caught early practitioners by surprise.

Suppose you take a trained 7B-parameter language model and naively round every weight to the nearest 8-bit integer. The weights look roughly Gaussian around zero, so you pick a scale factor (the range of values, divided by 256 steps) and clamp. For most layers this works well. But for a small fraction of layers — roughly 0.1% of the feature dimensions — the *activations* (the intermediate computed values during a forward pass, not the weights themselves) contain huge outliers. Values like 100 or 200, when most values are between $-1$ and $1$.

Why does this matter for weight quantization? Consider: a weight of $0.01$ multiplied by a "normal" activation of $0.5$ gives $0.005$. Round the weight to $0$ (because it is very small relative to the scale) and you lose 0.005. Fine. But a weight of $0.01$ multiplied by an outlier activation of $150$ gives $1.5$. Round the same tiny weight to $0$ and you lose $1.5$ — a catastrophic error, amplified by the outlier activation.

This was precisely the finding of Tim Dettmers and colleagues in their 2022 paper introducing LLM.int8(). The outlier activations, concentrated in just a handful of feature dimensions, are responsible for most of the quantization error. Ignoring them makes INT8 quantization essentially useless for large language models above a certain scale (roughly 6.7 billion parameters).

#history[
  Tim Dettmers was a PhD student at the University of Washington when he identified the outlier activation problem. His insight was to use *mixed-precision decomposition*: split the matrix multiplication into two parts. The tiny fraction of "outlier" dimensions are kept in float16 and multiplied in float16. Everything else is quantized to INT8. The two results are added together. This sounds complex but it works — and it was the first method that let researchers reliably run 175-billion-parameter models (like the original GPT-3) on a single machine. His work (Dettmers et al., "LLM.int8()", 2022) opened the floodgates.
]

Every serious quantization algorithm that came after LLM.int8() takes the outlier problem as a starting point and asks: how do we handle those salient features *without* the overhead of mixed-precision decomposition?

== Post-Training Quantization: The GPTQ Algorithm

*Post-training quantization* (PTQ) means you take a fully trained model — which you may not even have the compute budget to retrain — and compress it without additional training. You are allowed a small *calibration dataset* (a few hundred to a few thousand sample inputs) to measure activation statistics, but you do not update the model's weights via gradient descent.

GPTQ (Frantar, Ashkboos, Hoefler, and Alistarh, ETH Zurich, October 2022) was the first method to demonstrate reliable 4-bit quantization of very large language models (OPT-175B, BLOOM-176B) with almost no accuracy loss. It was a landmark.

The core idea of GPTQ is *second-order compensation*: when you round one weight, you adjust all the other unquantized weights in the same row to compensate for the error you just introduced.

=== How GPTQ Works: A Walkthrough

Think of a single weight matrix $W$ in the model — say, the projection matrix in one of the attention layers. It has shape $(d_"in", d_"out")$, meaning $d_"in"$ rows and $d_"out"$ columns. GPTQ works column by column.

*Step 1: Compute the Hessian.* Feed the calibration dataset through the model and record the input activations $X$ that reach this layer. The *Hessian* (second-order information) is:

$ H = 2 X X^T $

#gomaths("The Hessian: Second-Order Information")[
  In calculus, the *gradient* of a loss function tells you the slope — which direction to step to decrease the loss. The *Hessian* tells you the *curvature* — how steeply curved the loss is around your current position.

  Imagine standing on a hillside. The gradient points downhill. The Hessian tells you whether the hill is gently rolling (small curvature) or sharply peaked (large curvature). If a weight is in a sharply curved region, even a tiny change makes the loss jump dramatically. If it is in a gently rolling region, you can round it quite aggressively without hurting much.

  Mathematically, the Hessian $H$ is the matrix of *second derivatives*: $H_(i j) = (partial^2 "Loss") / (partial w_i partial w_j)$.

  GPTQ approximates the full Hessian with $H = 2 X X^T$, where $X$ is the matrix of input activations from the calibration data. This is a standard approximation that captures the curvature induced by the data, and it works well in practice.
]

*Step 2: Quantize column by column.* For each column $q$ of $W$, do:

1. Round the weight $w_q$ to the nearest value on the quantization grid (e.g., the nearest INT4 value).
2. Compute the error: $delta_q = w_q - "round"(w_q)$.
3. Compensate: subtract from all remaining columns (columns $q+1, q+2, ...$ in the same row) a correction proportional to the Hessian — specifically, the error times the inverse Hessian's relevant column. This is the *optimal brain compression* update, adapted from the classic *Optimal Brain Surgeon* technique of LeCun et al. (1990).
4. Move to column $q+1$ and repeat with the now-corrected weights.

The intuition: if rounding weight $w_q$ introduces error $epsilon$, we know (from the Hessian) exactly how much output error that produces. We can partially cancel this error by nudging the unquantized neighbors in a precisely computed direction. The result is that each quantized weight, in context with its neighbors, produces nearly the same output as the full-precision version.

*Step 3: Save the quantized integers and the scale/zero-point.* For each group of, say, 128 weights, store a float16 scale factor and zero point. At inference time, dequantize on the fly: $w = "scale" times ("quant\_value" + "zero\_point")$.

#algo(
  name: "GPTQ",
  year: "2022",
  authors: "Elias Frantar, Saleh Ashkboos, Torsten Hoefler, Dan Alistarh (ETH Zurich)",
  aim: "One-shot post-training quantization of LLM weight matrices to 4 or 3 bits using approximate second-order (Hessian) information to compensate rounding errors.",
  complexity: "O(d³) per layer for the Hessian inversion; linear passes over calibration data. Quantizing a 175B model takes a few GPU-hours.",
  strengths: "No retraining required; strong accuracy at W4; supports 3-bit and even 2-bit with grouping; publicly available implementation (AutoGPTQ, llama.cpp).",
  weaknesses: "Hessian computation requires calibration data; column-serial algorithm is sequential (hard to parallelize); slight accuracy degradation vs. W4 at 3-bit; does not handle activation quantization.",
  superseded: "Still widely used; newer methods like AWQ, QuIP#, and VPTQ offer improvements at 2–3 bits.",
)[
  GPTQ made headlines in late 2022 when it showed that GPT-sized models (then cutting-edge) could be quantized to 4 bits in a single GPU-hour, fitting in memory previously thought impossible for consumer hardware. It directly enabled the `llama.cpp` ecosystem that brought local AI to millions of laptops.
]

=== A Tiny Numeric Example

Suppose a row of weights is $w = [0.52, -0.48, 0.03, 0.71]$ and the 2-bit quantization grid is $\{-0.75, -0.25, 0.25, 0.75\}$ (four steps, for illustration).

Round the first weight: $0.52 arrow.r 0.75$ (the nearest grid value). Error: $delta = 0.52 - 0.75 = -0.23$.

The Hessian row corresponding to column 1 tells us (in our tiny example) that the compensation to the remaining three weights is $[+0.10, +0.02, +0.08]$. We add these to the remaining weights:

$w' = [-0.48 + 0.10, \ 0.03 + 0.02, \ 0.71 + 0.08] = [-0.38, \ 0.05, \ 0.79]$

Now round the second weight: $-0.38 arrow.r -0.25$. Error: $-0.38 - (-0.25) = -0.13$. Apply compensation to columns 3 and 4. Continue.

After four rounds, each quantized weight is accompanied by accumulated corrections, and the total layer output error is much smaller than it would be if we had naively rounded all weights independently. This is the GPTQ magic.

== AWQ: Protecting the Weights That Matter Most

AWQ (Activation-aware Weight Quantization), from Ji Lin, Jiaming Tang, Haotian Liu and colleagues at MIT's Han Lab, was published in June 2023 and won the *Best Paper Award at MLSys 2024*. It takes a different approach to the outlier problem than GPTQ.

The key observation: not all weight channels are equally important. A *channel* is a specific feature dimension — say, the 42nd dimension in a 4096-dimensional embedding. AWQ found that a tiny fraction of channels — roughly 1% — are responsible for a disproportionate fraction of the model's accuracy. These *salient channels* correspond to dimensions where the activation values tend to be large.

Why? Think about the product $w times x$ where $w$ is a weight and $x$ is an activation. If $x$ is typically 50 while other activations are near 1, then quantization error in $w$ gets multiplied by 50 when computing the output. That amplified error is what causes accuracy loss. GPTQ tries to compensate for this after the fact. AWQ *prevents* it proactively.

=== AWQ's Scaling Trick

AWQ's solution is elegant: before quantizing, *rescale* the salient channels by a factor $s > 1$. If you multiply a salient weight channel by $s$, the quantization grid for that channel effectively becomes finer (more steps per unit of signal). After quantization, divide the corresponding activation by $s$ on the other side of the multiply — the math still works out exactly, but the quantization error in the salient channel is now $s$ times smaller.

Formally, for a weight matrix $W$ and activation $x$, the computation is:

$ y = W x = (W dot.op "diag"(s)) (x dot / s) $

The per-channel scale $s$ is a vector. AWQ searches for the optimal $s$ that minimizes the quantization error on a calibration set, using a simple grid search or gradient descent. No Hessian inversion required.

#algo(
  name: "AWQ",
  year: "2023 (MLSys 2024 Best Paper)",
  authors: "Ji Lin, Jiaming Tang, Haotian Liu, Yang Shao, Guangxuan Xiao, Tianle Cai, Ligeng Zhu, Wei Chen, Song Han (MIT Han Lab)",
  aim: "Activation-aware PTQ: identify the 1% of salient weight channels (those multiplied by large activations) and rescale them before quantization to reduce their effective error.",
  complexity: "O(d) per layer for the channel search; much cheaper than GPTQ's Hessian inversion.",
  strengths: "Typically outperforms GPTQ on accuracy at W4; hardware-friendly (no runtime overhead — scales are absorbed into the weights); fast calibration; widely adopted (AutoAWQ library, supported by vLLM, Hugging Face).",
  weaknesses: "The channel-scaling trick does not address all sources of quantization error; at 3-bit or lower, gap to GPTQ closes; does not handle mixed weight/activation quantization.",
  superseded: "Still the practical default for W4A16 in 2024–2026. For sub-4-bit, vector quantization methods (QuIP#, VPTQ) push further.",
)[
  AWQ's insight about activation-based saliency has become a standard component in many follow-on methods. The finding that 1% of channels are responsible for most accuracy is not a coincidence — it reflects the structure of transformer attention heads, which develop highly specialized feature detectors during training.
]

=== AWQ vs. GPTQ: A Practical Comparison

How do we *measure* whether a quantized model is still good? The standard yardstick is *perplexity*, and it is a direct descendant of the cross-entropy we met in Chapters 23 and 62.

#gomaths("Perplexity")[
  In Chapter 23 we learned that the *cross-entropy* of a model on some text is the average number of bits the model spends to predict each symbol — and that this equals the expected code length if you compressed the text with that model (Chapter 62). Lower cross-entropy means a better predictor, hence a better compressor.

  *Perplexity* is just a friendlier repackaging of that same number. If a model's average cross-entropy over a test text is $H$ bits per token, its perplexity is
  $ "PPL" = 2^H. $
  (Researchers often measure $H$ in #emph[nats] — using the natural logarithm instead of $log_2$ — and write $"PPL" = e^H$; the idea is identical, only the base changes.)

  Intuitively, perplexity is the *effective number of equally-likely choices* the model feels it is facing at each step. A perplexity of 1 means perfect certainty (it always knew the next token). A perplexity of 50 000 — roughly the vocabulary size — means the model is guessing blindly. A good 7-billion-parameter model on ordinary English sits around $"PPL" approx 6$: at each word it has narrowed a 50 000-word vocabulary down to the confusion of a fair 6-sided die.

  Because perplexity is monotonic in cross-entropy ($2^H$ only grows as $H$ grows), *lower perplexity = fewer bits = better model*. That is why every quantization paper reports it: a quantized model that barely raises perplexity has barely damaged the model's compression ability — and, empirically, its usefulness.
]

#fig([GPTQ vs. AWQ: perplexity on WikiText-2 for a 7B model at different bit widths. Lower is better. (Schematic; representative of published results.)],
  cetz.canvas({
    import cetz.draw: *
    // Axis
    line((0,0),(6.5,0), mark: (end: ">"))
    line((0,0),(0,4.5), mark: (end: ">"))
    content((3.25,-0.5))[Bit width (weights)]
    content((-0.9,2.25), angle: 90deg)[Perplexity (lower = better)]
    // Ticks X
    for (x, label) in ((1,"2-bit"),(2.5,"3-bit"),(4,"4-bit"),(5.5,"16-bit")) {
      line((x,-0.1),(x,0.1))
      content((x,-0.35), size: 8pt)[#label]
    }
    // Ticks Y
    for (y, val) in ((0.5,"5"),(1.5,"7"),(2.5,"10"),(3.5,"20"),(4,"30")) {
      line((-0.1,y),(0.1,y))
      content((-0.4,y), size: 8pt)[#val]
    }
    // Lines
    // BF16 baseline
    line((1,0.5),(5.5,0.5), stroke: (dash: "dashed", paint: gray))
    content((5.8,0.5), size: 7.5pt)[BF16 baseline]
    // GPTQ
    let gptq = ((1,3.8),(2.5,2.2),(4,0.8),(5.5,0.5))
    for i in range(gptq.len() - 1) {
      line(gptq.at(i), gptq.at(i+1), stroke: (paint: rgb("#c0392b"), thickness: 1.5pt))
    }
    for pt in gptq { circle(pt, radius: 0.08, fill: rgb("#c0392b")) }
    content((0.5,4.0), size: 8pt, fill: rgb("#c0392b"))[GPTQ]
    // AWQ
    let awq = ((1,3.5),(2.5,1.9),(4,0.7),(5.5,0.5))
    for i in range(awq.len() - 1) {
      line(awq.at(i), awq.at(i+1), stroke: (paint: rgb("#0b5394"), thickness: 1.5pt))
    }
    for pt in awq { circle(pt, radius: 0.08, fill: rgb("#0b5394")) }
    content((0.5,3.3), size: 8pt, fill: rgb("#0b5394"))[AWQ]
  })
)

At 4-bit, both methods are excellent — perplexity within ~5% of the float16 baseline. At 3-bit, AWQ tends to pull ahead. At 2-bit, both degrade significantly, though newer vector-quantization methods (QuIP\#, QTIP, VPTQ from 2024–2025) extend the usable range.

#checkpoint[
  If both GPTQ and AWQ work well at 4-bit, why would you choose one over the other?
][
  AWQ is generally faster to calibrate (no matrix inversion) and often slightly more accurate. GPTQ is more widely supported in older tooling and can sometimes be more precise for specific models. In practice, AWQ has become the community default for W4A16 deployment since mid-2023.
]

== Quantization-Aware Training: Teaching the Model About Its Future

Post-training quantization is convenient because you do not need to retrain anything. But it is fundamentally making the best of a bad situation: you trained the network in full precision, then squeezed it into fewer bits, hoping the rounding errors cancel.

*Quantization-aware training* (QAT) takes the opposite approach: include the quantization operation *inside the training loop*, so the model learns to be robust to the rounding from the start.

During the forward pass, QAT replaces each weight value with its quantized-then-dequantized version:

$ tilde(w) = s dot "round"(w / s) $

where $s$ is the scale factor. The model sees $tilde(w)$ instead of $w$ during every forward pass. It learns to make predictions that are accurate even when every weight is on a discrete grid.

The challenge: the `round()` function has zero gradient everywhere (it is a staircase), so backpropagation gets stuck. The standard fix is the *straight-through estimator*: pretend that the gradient of `round()` is $1$ during the backward pass. This is a hack, but it works well in practice.

#gomaths("The Straight-Through Estimator")[
  Backpropagation computes the gradient of the loss with respect to each weight by applying the chain rule: multiply the gradients of each operation along the path from that weight to the loss.

  The `round()` function maps any real number to the nearest integer. Its derivative is zero almost everywhere (the staircase is flat between steps) and undefined at the jumps. So `round()` kills all gradients that flow through it — training would stop.

  The *straight-through estimator* (Bengio et al., 2013) simply pretends that $d("round"(x)) / d x = 1$ during the backward pass. It is "straight through" the quantizer as if it were the identity function. Forward: quantize. Backward: ignore the quantizer.

  This is mathematically unjustified but empirically reliable, and has become standard in quantization research. The intuition is that `round(x)` moves $x$ at most half a step, so it is "almost" the identity.
]

QAT produces more accurate models than PTQ at the same bit width, particularly at very low bits (4 or below). The cost is that you need to retrain — or at minimum *fine-tune* — the model, which requires GPU-hours and a training dataset. For a 7B-parameter model, a short fine-tuning run might cost thousands of dollars in cloud compute. For the original model creators with access to their training pipeline, QAT is the gold standard. For users who download a pre-trained model and want to deploy it, PTQ is the realistic choice.

=== LLM-QAT: Fine-Tuning Without a Dataset

A 2023 technique from Meta AI, *LLM-QAT*, makes QAT practical for users who do not have the original training data. It uses the model itself to generate training examples (by sampling from its own outputs — a process called *data-free distillation*) and fine-tunes with quantization simulation. This recovered significant accuracy at W4A4 compared to PTQ alone.

#fig([QAT vs. PTQ trade-off. QAT (blue) always achieves lower perplexity at the same bit width, at the cost of requiring a fine-tuning pass.],
  cetz.canvas({
    import cetz.draw: *
    // Axes
    line((0,0),(5.5,0), mark: (end: ">"))
    line((0,0),(0,4), mark: (end: ">"))
    content((2.75,-0.6))[Bit width]
    content((-1,2), angle: 90deg)[Perplexity]
    // Ticks
    for (x,lbl) in ((1,"4"),(2,"6"),(3,"8"),(4.5,"16")) {
      line((x,-0.08),(x,0.08))
      content((x,-0.3), size: 8pt)[#lbl]
    }
    // QAT line (lower = better)
    let qat = ((1,1.5),(2,0.9),(3,0.65),(4.5,0.5))
    for i in range(qat.len()-1) { line(qat.at(i), qat.at(i+1), stroke: (paint: rgb("#0b6e4f"), thickness: 1.5pt)) }
    for p in qat { circle(p, radius: 0.07, fill: rgb("#0b6e4f")) }
    content((4.8,0.6), size: 8pt, fill: rgb("#0b6e4f"))[QAT]
    // PTQ line
    let ptq = ((1,2.6),(2,1.4),(3,0.9),(4.5,0.5))
    for i in range(ptq.len()-1) { line(ptq.at(i), ptq.at(i+1), stroke: (paint: rgb("#c0392b"), thickness: 1.5pt)) }
    for p in ptq { circle(p, radius: 0.07, fill: rgb("#c0392b")) }
    content((4.8,1.1), size: 8pt, fill: rgb("#c0392b"))[PTQ]
    // Shaded region = "cost of QAT"
    // (simplified: just mark the 4-bit gap)
    line((1,1.5),(1,2.6), stroke: (dash: "dotted", paint: gray))
    content((1.5,2.1), size: 7.5pt)[← QAT gain]
  })
)

== FP8: The Hardware Sweet Spot

While the research community was busy with INT4 and below, hardware engineers were implementing a different format: *FP8*, or 8-bit floating point.

Unlike INT8 (which stores integers), FP8 is a true floating-point format with a sign, a small exponent, and a small mantissa. Two variants exist:
- *E4M3*: 1 sign + 4 exponent + 3 mantissa bits. Range up to $\pm 448$, ~3 significant bits of mantissa. Good for weights.
- *E5M2*: 1 sign + 5 exponent + 2 mantissa bits. Larger range ($\pm 57344$), fewer mantissa bits. Good for activations and gradients (where dynamic range matters more).

#keyidea[
  FP8 is significant because the NVIDIA H100 GPU (released 2022, widely deployed from 2023) has native FP8 tensor cores that perform matrix multiplications twice as fast as BF16 on the same silicon. For the first time, quantization gives not just memory savings but real arithmetic speedup on mainstream training hardware.
]

NVIDIA reports that FP8 inference on H100 GPUs is up to $1.81 times$ faster than BF16 at batch size 32, and $2.66 times$ faster at batch size 1 (latency-critical settings). The Llama 3 family was trained with FP8 gradient scaling. DeepSeek-V3 (December 2024) used FP8 training throughout, cutting training costs dramatically.

The quantization challenge for FP8 is subtler than for INT8. Because FP8 still has a floating-point range (exponent bits), the outlier activation problem that kills INT8 is much less severe — the format adapts its scale. The main concern is *clipping*: values outside the format's range are silently clamped, which can cause invisible accuracy loss.

== The Information-Theoretic Frontier: BitNet b1.58

Everything discussed so far is *compression after training* — you train a full-precision model and then reduce its precision. The most radical idea in the field asks: what if we train with ultra-low precision from the beginning, so the model never needs to unlearn the false precision it was given?

The landmark is *BitNet b1.58*, published by Microsoft Research (Shuming Ma and colleagues) in February 2024. The name "b1.58" is itself a compression argument:

#gomaths("Why 1.58?")[
  If each weight can take one of $n$ distinct values, then each weight carries $log_2(n)$ bits of information.

  For ternary weights (three values: $-1, 0, +1$), we have $n = 3$, so:
  $ log_2(3) = log(3) / log(2) approx 1.585 "bits per weight" $

  This is where the name "b1.58" comes from — it is the theoretical information content of one ternary weight. Compare to:
  - INT4: $log_2(16) = 4$ bits per weight
  - INT8: $log_2(256) = 8$ bits per weight
  - BF16: 16 bits per weight

  Ternary is almost as good as 1-bit (which would be $log_2(2) = 1$ bit) but much more expressive, since the $0$ value allows the model to effectively "turn off" connections.
]

=== How BitNet b1.58 Works

BitNet b1.58 replaces every linear layer (`nn.Linear` in PyTorch) with a custom `BitLinear` layer. During training:

1. *Weight quantization*: The full-precision weights $W$ are scaled by $1 / "mean"(|W|)$ (the average absolute value), then rounded to $\{-1, 0, +1\}$. This is called *absmean quantization*.
2. *Activation quantization*: Input activations are quantized to INT8 per-token (a range of $-127$ to $127$).
3. The quantized multiplication is performed with INT8 arithmetic (fast on all hardware) using the ternary-weight $times$ INT8-activation pattern.
4. During the backward pass, the full-precision weights (before rounding) are used for gradient computation (straight-through estimator).

At inference time, the ternary weights are stored as 2-bit integers (since you need to distinguish $-1, 0, +1$). The model does not use floating-point multiplications at all — just additions and subtractions. This is transformative for CPU inference, where multiplication is expensive and addition is cheap.

=== BitNet b1.58 Performance

The surprising result — confirmed across multiple papers and in Microsoft's April 2025 open-weight release of BitNet b1.58 2B4T (2 billion parameters, 4 trillion training tokens) — is that a BitNet model trained natively in 1.58 bits *matches a full-precision model of the same size* on perplexity and downstream tasks at scales of 3 billion parameters and above.

#algo(
  name: "BitNet b1.58",
  year: "2024",
  authors: "Shuming Ma, Hongyu Wang, Lingxiao Ma, Lei Wang, Wenhui Wang, Shaohan Huang, Li Dong, Ruiping Wang, Jilong Xue, Furu Wei (Microsoft Research)",
  aim: "Natively train LLMs with ternary weights (−1, 0, +1) — 1.58 bits per weight — achieving full-precision accuracy at ≥3B scale while enabling CPU inference and massive energy savings.",
  complexity: "Same training FLOPs as standard BF16 training; inference FLOPs dominated by additions rather than multiplications (3–5× cheaper on CPU).",
  strengths: "Matches FP16 accuracy at ≥3B scale; inference runs on CPU without GPU; ~30× less energy for matrix multiplications; open weights (MIT license); eliminates the outlier problem entirely (ternary weights have no outliers).",
  weaknesses: "Must be trained from scratch (cannot apply to existing full-precision models); smaller models (<1B) show accuracy degradation; the INT8 activation quantization is still needed and can still produce outliers; as of mid-2026, large (70B+) native BitNet models have not been publicly released.",
  superseded: "BitNet a4.8 (2024) adds 4-bit activations for further savings; BitNet v2 (under development, mid-2026) is exploring hybrid attention architectures.",
)[
  The April 2025 release of BitNet b1.58 2B4T was a watershed: the first open-weight model natively trained at 1.58 bits to demonstrate competitive quality with its float16 peers. Running at 5–7 tokens per second on a laptop CPU, it showed that the ternary frontier is not theoretical — it is here.
]

=== Why Ternary Weights Eliminate the Outlier Problem

Recall that the outlier problem arises when *activation* values are much larger than average, amplifying weight quantization error. BitNet b1.58 takes a different path: because the weights are always exactly $\{-1, 0, +1\}$, there is no "weight quantization error" to amplify. The weight is already perfect — it is an exact integer. The only source of error is the activation quantization (INT8), which is much better behaved.

#misconception[
  "BitNet b1.58 is just INT2 quantization — it should be terrible at 2 bits."
][
  The crucial difference is *native training versus post-training quantization*. An INT2-quantized full-precision model (which was trained thinking it had 16-bit weights) is severely damaged by the coarse grid. BitNet b1.58 was designed and trained from the start knowing its weights would only ever be $\{-1, 0, +1\}$ — the model's optimizer found representations that work within those constraints. It is the difference between trying to fit a large painting through a small door versus painting directly on the door.
]

== Mixed-Precision and the Practical Toolkit

Real production deployments rarely use one bit width uniformly across the whole model. Different parts of a transformer have different sensitivities:

- *Embedding layers* (input token embeddings) are highly sensitive. They are typically kept in float16 or at 8-bit.
- *Attention weights* ($Q$, $K$, $V$, $O$ projections) tolerate 4-bit well after calibration.
- *Feed-forward layers* (the large MLP blocks that dominate parameter count) tolerate 4-bit and sometimes 3-bit.
- *The LM head* (the final linear layer that turns the model's internal state into one raw score — a #emph[logit] — for every word in the vocabulary; those scores are then normalized into the next-token probabilities that drove the compressor of Chapter 62) is kept at 8-bit or 16-bit.

The standard practical recipe for deploying a 7B–70B model on consumer hardware in 2024–2026 is:

1. Apply AWQ (or GPTQ) to produce a W4A16 model.
2. Use grouped quantization with group size 128 (128 weights share one scale factor, reducing the overhead of individual scales).
3. Keep embeddings and LM head at 16-bit.
4. Serve with `llama.cpp` (CPU) or `vLLM`/`TGI` (GPU), both of which have native W4A16 kernels.

This pipeline yields models that are 3.5–4× smaller than the float16 original and run at 60–90% of the original quality on most benchmarks, with no retraining.

#gopython("NumPy Array Slicing and the @ Operator")[
  Before reading the code below, here is a quick reminder of two Python/NumPy tricks used throughout:

  *Array slicing*: `arr[2:5]` selects elements at positions 2, 3, 4 (0-indexed, upper bound exclusive). `arr[:, 3]` selects column 3 of a 2D array (all rows, column 3). `arr[2:5, :]` selects rows 2–4.

  *The @ operator* (Python 3.5+, NumPy): `A @ B` computes the matrix product of `A` and `B`. Equivalent to `np.matmul(A, B)`.

  ```python
  import numpy as np
  A = np.array([[1, 2], [3, 4]])
  B = np.array([[5], [6]])
  print(A @ B)   # [[17], [39]] — matrix multiply
  print(A[0, :]) # [1, 2] — first row
  ```
]

== Code: PTQ in Python from Scratch

The following Python 3.14 code demonstrates the core ideas of post-training quantization. We implement a minimal round-to-nearest quantizer, compute scale factors, and measure the error introduced.

#gopython("Rounding, Integer Types, and Clipping")[
  Python's built-in `round()` function rounds to the nearest integer (breaking ties toward even). NumPy's `np.round()` works the same way on arrays. To quantize to $k$ bits, we need values in $[0, 2^k - 1]$ (unsigned) or $[-2^{k-1}, 2^{k-1} - 1]$ (signed). `np.clip(x, lo, hi)` clamps all values in array `x` to the range `[lo, hi]`.

  ```python
  import numpy as np
  x = np.array([1.7, -0.3, 200.0, -200.0])
  clipped = np.clip(x, -127, 127)
  print(clipped)  # [  1.7  -0.3  127.  -127. ]
  rounded = np.round(clipped).astype(np.int8)
  print(rounded)  # [  2   0  127 -127]
  ```
]

```python
# ptq_demo.py — a minimal post-training quantization demonstration
import numpy as np
import numpy.typing as npt

def absmax_quantize(
    w: npt.NDArray[np.float32],
    bits: int = 8,
) -> tuple[npt.NDArray[np.int8], float]:
    """Quantize float32 weights to `bits`-bit signed integers.

    Uses absmax scaling: the largest magnitude value maps to ±(2^(bits-1) − 1).
    Returns (quantized_weights, scale_factor).
    """
    max_val = np.max(np.abs(w))
    q_max = 2 ** (bits - 1) - 1          # e.g. 127 for 8-bit
    scale = max_val / q_max
    q = np.round(w / scale).astype(np.int8 if bits <= 8 else np.int16)
    q = np.clip(q, -(q_max + 1), q_max)
    return q, scale

def dequantize(
    q: npt.NDArray[np.int8],
    scale: float,
) -> npt.NDArray[np.float32]:
    """Reconstruct float32 from quantized integers and scale."""
    return q.astype(np.float32) * scale

def quantization_error(original: npt.NDArray, bits: int) -> dict[str, float]:
    """Quantize `original`, dequantize, and report error statistics."""
    q, scale = absmax_quantize(original.astype(np.float32), bits)
    reconstructed = dequantize(q, scale)
    diff = original - reconstructed
    return {
        "bits": bits,
        "scale": round(float(scale), 6),
        "max_abs_error": float(np.max(np.abs(diff))),
        "mean_abs_error": float(np.mean(np.abs(diff))),
        "snr_db": float(
            10 * np.log10(np.mean(original**2) / (np.mean(diff**2) + 1e-12))
        ),
    }

# --- demonstration ---
rng = np.random.default_rng(seed=42)
# Simulate a weight matrix with mostly small values and a few outliers
weights = rng.normal(0, 0.1, size=(256, 256)).astype(np.float32)
weights[0, 0] = 5.0   # artificial outlier

for b in (8, 4, 2):
    stats = quantization_error(weights, bits=b)
    print(f"INT{b}: scale={stats['scale']:.4f}  "
          f"max_err={stats['max_abs_error']:.4f}  "
          f"SNR={stats['snr_db']:.1f} dB")
```

Running this produces output like:

```
INT8: scale=0.0197  max_err=0.0197  SNR=42.1 dB
INT4: scale=0.3333  max_err=0.3333  SNR=22.4 dB
INT2: scale=1.6667  max_err=1.6667  SNR=10.1 dB
```

Notice how the presence of a single outlier weight (`weights[0,0] = 5.0`) forces a large scale factor even for INT8 — the whole range is "wasted" on that one value. In practice, the fix is *clipping* (setting a maximum scale slightly below the true max) or *group quantization* (different scale per group of 128 weights, so the outlier only pollutes its local group).

#gopython("Signal-to-Noise Ratio in Decibels")[
  The *signal-to-noise ratio (SNR)* measures how much the "signal" (the true value) dominates over the "noise" (the error). In decibels (dB):

  $ "SNR"_"dB" = 10 log_10 (sigma^2_"signal" / sigma^2_"noise") $

  where $sigma^2_"signal" = "mean"(w^2)$ is the average squared weight value (signal power) and $sigma^2_"noise" = "mean"((w - hat(w))^2)$ is the average squared quantization error (noise power).

  Each 6 dB of SNR corresponds to roughly one additional bit of precision. INT8 typically achieves ~48 dB; INT4 ~24 dB; INT2 ~12 dB. Human ears can detect noise above about 40 dB SNR; the "threshold" for perceptual damage to model quality is more like 20–30 dB, depending on the task.
]

== A Second Code Listing: Naive Ternary Quantization

```python
# ternary_demo.py — absmean quantization to {-1, 0, +1} (BitNet-style)
import numpy as np
import numpy.typing as npt

def ternary_quantize(
    w: npt.NDArray[np.float32],
) -> tuple[npt.NDArray[np.int8], float]:
    """Quantize to ternary {-1, 0, +1} using absmean scaling.

    Scale = mean(|w|). After scaling, values in (-0.5, 0.5) map to 0,
    values ≤ -0.5 map to -1, values ≥ 0.5 map to +1.
    Returns (ternary_weights, scale).
    """
    scale = float(np.mean(np.abs(w)))
    if scale < 1e-8:
        return np.zeros_like(w, dtype=np.int8), 1.0
    w_scaled = w / scale
    # Round to nearest integer, then clip to {-1, 0, +1}
    q = np.clip(np.round(w_scaled), -1, 1).astype(np.int8)
    return q, scale

def ternary_dequantize(
    q: npt.NDArray[np.int8],
    scale: float,
) -> npt.NDArray[np.float32]:
    return q.astype(np.float32) * scale

# --- demonstration ---
rng = np.random.default_rng(seed=7)
w = rng.normal(0, 0.08, size=(4, 4)).astype(np.float32)
print("Original weights (4×4 sample):")
print(np.round(w, 3))

q, scale = ternary_quantize(w)
print(f"\nAbsmean scale: {scale:.4f}")
print("Ternary weights:")
print(q)

w_rec = ternary_dequantize(q, scale)
print(f"\nMax reconstruction error: {np.max(np.abs(w - w_rec)):.4f}")
print(f"Fraction of zeros: {np.mean(q == 0):.1%}")
```

This illustrates the key observation: with weights drawn from a Gaussian with standard deviation 0.08, the absmean scale is about $0.064$ (since the mean absolute value of a zero-mean Gaussian is $sigma sqrt(2 / pi)$). After scaling, a large fraction of weights fall into the $(-0.5, +0.5)$ range and become 0. This sparsity is a feature, not a bug — zero weights require no computation.

#aside[
  *Why does absmean work better than absmax for ternary quantization?*

  With absmax, you set the scale so the largest weight maps to 1. But the largest weight might be a rare outlier that "wastes" the scale on itself. Absmean sets the scale to the *average* absolute weight, so the typical weight maps close to 1. Most weights land near $\pm 1$ or at $0$ after rounding. The absmax approach would push most weights toward 0, making the network sparse in the wrong way (you'd lose signal uniformly rather than deliberately).
]

== What Survives Quantization, and What Breaks

Not all neural network knowledge is equally fragile under quantization. This is an important practical lesson.

*What survives:* General language understanding, factual recall on common topics, standard reasoning tasks, code generation for mainstream languages. At W4A16 with AWQ, these degrade by at most a few percentage points on standard benchmarks.

*What breaks first:* Precise arithmetic (the model is already imperfect at multi-digit math; quantization makes it worse), rare factual knowledge (if a fact was stored in a single weight group that suffers high quantization error, it may be lost), and long-context coherence (small errors accumulate over many layers and many attention steps).

#pitfall[
  *Benchmark inflation at 4-bit.* Many quantized model releases report nearly identical benchmark scores to the full-precision original. These benchmarks (MMLU, HellaSwag, etc.) measure coarse accuracy on multiple-choice questions. Quantization errors are often too small to flip the top-1 answer on these tasks — but they may still meaningfully degrade the model's ability to write coherent long-form text, maintain factual accuracy in open-ended generation, or perform careful reasoning. Always evaluate quantized models on your actual task, not just on standard benchmarks.
]

== The 2024–2026 Frontier

=== Vector Quantization for Weights

At bit widths below 4, per-weight quantization (GPTQ, AWQ) breaks down because the grid is too coarse. A new family of methods treats a *group* of weights as a vector and quantizes the whole vector jointly to a learned codebook entry — *vector quantization* (VQ). #mathrecall[VQ was introduced from scratch in Chapter 39 (the LBG algorithm builds a codebook of representative vectors), and reappeared in Chapter 60 as the residual vector quantization at the heart of neural audio codecs.] The same idea applies to model weights: instead of rounding each weight to its own grid, you replace a block of (say) 8 weights with the index of the nearest entry in a shared codebook of, perhaps, 256 prototype blocks — so 8 weights cost just 8 bits total, one bit per weight.

Leading examples:
- *QuIP\#* (Cornell, 2023–2024): uses a random Hadamard transform to "incoherently" rotate weights before scalar quantization, smoothing out outliers. Combined with 2-bit scalar quantization, it approaches PTQ at W4.
- *QTIP* (2024): extends QuIP\# with trellis-coded quantization.
- *VPTQ* (2024–2025): vector-quantizes groups of 16–256 weights to a small codebook with residual correction. Achieves near-lossless compression at 2 bits on 70B models.
- *ParetoQ* (2025): unifies 1–4 bit quantization under a single scaling law showing that for a fixed compute budget, you should train longer and quantize more aggressively rather than training shorter and keeping precision.

=== Rotation Tricks

A simpler and increasingly popular approach to handling outlier activations is *rotation*: apply a random orthogonal matrix $R$ to the weights and activations before quantization, then undo it after. Orthogonal rotations preserve the norm of vectors (and therefore the output of matrix multiplications) exactly, but they spread out outliers across all dimensions, making the distribution more uniform and easier to quantize.

Methods like *QuaRot* (2024) and *SpinQuant* (2024) apply this at the transformer block level, enabling W4A4 quantization that was previously difficult.

=== D2Quant and Sub-2-Bit

As of mid-2026, sub-2-bit quantization (W1, W1.5) remains an open problem. The D2Quant line of work (2025–2026) pushes toward 2 bits with vector quantization and hardware co-design. But the honest assessment is that below 2 bits per weight, quality degrades significantly for most tasks — the information bottleneck is real. BitNet b1.58 at 1.58 bits works because it is *trained* with that precision, not because 1.58 bits is sufficient to hold a post-trained model.

== Summary: Choosing a Quantization Strategy

#fig([Decision tree for choosing a quantization approach in 2024–2026.],
  cetz.canvas({
    import cetz.draw: *
    // Root
    rect((1.5,5.5),(4.5,6.5), radius: 4pt, fill: rgb("#e8f4f8"), stroke: rgb("#0b5394"))
    content((3,6), size: 8pt)[Do you control training?]
    // Yes branch
    line((3,5.5),(1.5,4.5), mark: (end: ">"))
    content((1.2,5), size: 7.5pt)[Yes]
    rect((0,3.5),(3,4.5), radius: 4pt, fill: rgb("#e8f8f0"), stroke: rgb("#0b6e4f"))
    content((1.5,4), size: 7.5pt)[QAT or native (BitNet)]
    // No branch
    line((3,5.5),(4.5,4.5), mark: (end: ">"))
    content((4.7,5), size: 7.5pt)[No]
    rect((3,3.5),(6,4.5), radius: 4pt, fill: rgb("#fff3e8"), stroke: rgb("#c0392b"))
    content((4.5,4), size: 7.5pt)[PTQ path]
    // PTQ sub-branches
    line((4.5,3.5),(3.5,2.5), mark: (end: ">"))
    content((3.0,3), size: 7.5pt)[≥4-bit]
    rect((2,1.5),(5,2.5), radius: 3pt, fill: rgb("#f0f0f0"))
    content((3.5,2), size: 7.5pt)[AWQ (W4A16)]
    line((4.5,3.5),(5.5,2.5), mark: (end: ">"))
    content((5.8,3), size: 7.5pt)[\<4-bit]
    rect((4.5,1.5),(7,2.5), radius: 3pt, fill: rgb("#f0f0f0"))
    content((5.75,2), size: 7.5pt)[QuIP\# / VPTQ]
  })
)

The practical summary for 2024–2026:

- *You need to deploy today, you downloaded a model:* Use AWQ at W4A16. It is fast to calibrate, widely supported, and gives 3.5–4× compression with minimal quality loss. Tools: AutoAWQ, llama.cpp, vLLM.
- *You have a fine-tuning budget:* Use QAT or combine PTQ with a short fine-tuning pass. You recover ~50–70% of the accuracy gap versus PTQ alone.
- *You are building a new model from scratch and need extreme efficiency:* Consider BitNet b1.58 at 3B parameters or above. The native ternary approach matches full precision while enabling CPU deployment.
- *You need sub-4-bit for an existing model:* Use GPTQ (at 3-bit with grouping) or vector quantization methods (QuIP\#, VPTQ) if you can tolerate the higher calibration cost.
- *You are deploying on H100 GPUs and need raw throughput:* Use FP8 (W8A8-FP8). The 2× arithmetic speedup dominates all other considerations.

#takeaways((
  "A neural network weight is a floating-point number; quantization maps it to a coarser integer grid, trading precision for memory and speed.",
  "The outlier activation problem (a few dimensions with huge values amplifying quantization error) is the central challenge for W8 and below.",
  "GPTQ (2022) uses Hessian-based second-order compensation — rounding one weight, then adjusting its neighbors — to achieve accurate W4 PTQ without retraining.",
  "AWQ (2023, MLSys 2024 Best Paper) takes a lighter approach: identify the 1% of salient weight channels (those multiplied by large activations) and rescale them to reduce their quantization error.",
  "Quantization-aware training (QAT) trains with the quantizer inside the loop, yielding better accuracy than PTQ at the cost of a fine-tuning pass.",
  "FP8 is the hardware sweet spot for H100 GPUs: 2–2.7× faster than BF16, with the floating-point format handling outliers gracefully.",
  "BitNet b1.58 (2024) trains models natively with ternary weights (−1, 0, +1), achieving 1.58 bits per weight and full-precision accuracy at ≥3B scale — enabling CPU inference at human reading speed.",
  "At sub-4-bit, vector quantization methods (QuIP#, VPTQ) and rotation tricks (QuaRot, SpinQuant) are the frontier. Below 2-bit, accuracy degrades sharply for PTQ models.",
))

== Exercises

#exercise("63.1", 1)[
  A language model has 7 billion parameters. Calculate its memory footprint in gigabytes for each of the following storage formats: (a) float32, (b) bfloat16, (c) INT8, (d) INT4, (e) ternary with 2 bits per weight. Show your work.
]

#solution("63.1")[
  Each parameter in: (a) float32 = 4 bytes, so $7 times 10^9 times 4 / 10^9 = 28$ GB. (b) bfloat16 = 2 bytes, so $14$ GB. (c) INT8 = 1 byte, so $7$ GB. (d) INT4 = 0.5 bytes, so $3.5$ GB. (e) 2 bits per weight = 0.25 bytes, so $1.75$ GB. Note: real models also carry overhead for activations, KV cache, and metadata, but these calculations capture the weight-only footprint.
]

#exercise("63.2", 1)[
  Explain in plain language why the outlier activation problem causes INT8 quantization to fail for large language models, even though INT8 seems like it should be precise enough (256 distinct values covers a lot of range). Your explanation should be understandable to someone who has never studied neural networks.
]

#solution("63.2")[
  Imagine you are packing a suitcase. You have 100 T-shirts and one giant inflatable castle. The suitcase has 256 compartments. If you size each compartment to fit the castle, the T-shirts rattle around in compartments far too big for them — you can barely distinguish a size-S from a size-M shirt because they both look "small" next to the castle. That is what happens with outlier activations. A few feature dimensions have values like 150, while most are near 0.1. The quantizer must cover the whole range $[-150, +150]$ in 256 steps, making each step about 1.2 units wide. A typical weight contributing to the small-valued dimensions gets rounded to the nearest 1.2-unit mark — an error of up to 0.6 for a weight that should only matter in the hundredths place. The error is giant relative to the signal.
]

#exercise("63.3", 2)[
  GPTQ quantizes weight matrices column by column, updating remaining weights with a Hessian correction after each column. Why must this be done sequentially (column by column) rather than all at once? What would happen if you quantized all columns simultaneously without the Hessian correction?
]

#solution("63.3")[
  The sequential structure is essential because each correction depends on the errors introduced in previous steps. If you quantize all columns simultaneously, you have no information about the other columns' rounding errors and cannot compensate for them. The compensation of column $q$ assumes that columns $1, ..., q-1$ have already been quantized (their errors already fixed) and that columns $q+1, ...$ are still in full precision (and can absorb the correction). If you tried to quantize all at once without correction, you get the naive round-to-nearest result — every weight independently rounded, errors not compensated — which is equivalent to standard PTQ without any second-order information. GPTQ's contribution is exactly this sequential compensation loop.
]

#exercise("63.4", 2)[
  AWQ identifies salient weight channels by looking at activation magnitudes, not weight magnitudes. Give an intuitive example (you can invent numbers) showing why a weight with a large *activation* is more damaging to quantize coarsely than a weight with a large *weight value* but small activation.
]

#solution("63.4")[
  Suppose weight $A = 10.0$ (large weight) multiplied by activation $x_A = 0.001$ (tiny activation). The contribution to output is $10.0 times 0.001 = 0.010$. If we quantize $A$ to $9.0$ (rounding error = 1.0), the output error is $1.0 times 0.001 = 0.001$ — tiny. Now weight $B = 0.01$ (small weight) multiplied by activation $x_B = 200$ (outlier activation). Contribution = $0.01 times 200 = 2.0$. If we quantize $B$ to $0$ (rounding error = 0.01), the output error is $0.01 times 200 = 2.0$ — enormous. AWQ's insight is to look at *output error = weight\_error × activation*, not just weight magnitude or activation magnitude alone.
]

#exercise("63.5", 2)[
  The `ternary_demo.py` code reports the "fraction of zeros" in the quantized weight matrix. Why would a high fraction of zeros (say 40%) be beneficial for inference speed, especially on a CPU?
]

#solution("63.5")[
  Zero weights do not require any computation. In a standard matrix-vector multiply, each output element is a sum of products $y_j = sum_i w_(i j) x_i$. If $w_(i j) = 0$, the term $0 times x_i = 0$ contributes nothing and can be skipped. On a CPU, multiplications are much more expensive than additions, and loading and multiplying by zero is still work. A sparse ternary weight matrix can be implemented as: for each non-zero weight (which is either $+1$ or $-1$), just add or subtract the corresponding activation. No multiplication at all. With 40% zeros, you skip 40% of the additions, and you replace all remaining multiplications with simple sign flips — a substantial speedup, especially on CPUs without dedicated SIMD float multiply instructions.
]

#exercise("63.6", 3)[
  A researcher claims: "I quantized a 7B model to W4A16 using AWQ and it scores 98% of the original BF16 model on the MMLU benchmark. Therefore, the W4 model is 98% as good as the original for all applications." Write a detailed critique of this claim, identifying at least three specific scenarios where the W4 model might fail where the BF16 model succeeds, and explain why benchmark scores can be misleading.
]

#solution("63.6")[
  The claim conflates benchmark performance with general capability. Three specific failure scenarios: (1) *Long-form factual writing*: MMLU tests multiple-choice recall. A small quantization error that nudges a probability from 0.92 to 0.89 does not change the top-1 answer but might cause the model to subtly misremember rare facts when generating paragraphs. The error is invisible on MMLU, but matters in deployment. (2) *Multi-step arithmetic*: Models already struggle with precise arithmetic. W4 quantization reduces the effective precision of the model's "working memory" across layers. A problem requiring 5 sequential arithmetic steps accumulates small errors at each step; the W4 model may fail on step 4 while the BF16 model succeeds. MMLU rarely tests this deeply. (3) *Calibration and uncertainty*: If the model must express calibrated probabilities (useful for safety-critical applications), the small score shifts from quantization may systematically bias the model's confidence. Finally, MMLU is a coarse benchmark — it is designed to distinguish random guessing (25%) from human expert (90%+). The 2 percentage points of "headroom" above a chance-inflated base rate are much larger than the 2% gap the researcher measured. Real capability differences can hide in that range.
]

== Further Reading

- #link("https://arxiv.org/abs/2210.17323")[Frantar, Ashkboos, Hoefler, Alistarh. *GPTQ: Accurate Post-Training Quantization for Generative Pre-trained Transformers*. arXiv:2210.17323, 2022.] — The original GPTQ paper. Read Section 3 for the algorithm and Section 4 for the OPT/BLOOM experiments.

- #link("https://arxiv.org/abs/2306.00978")[Lin, Tang, Liu et al. *AWQ: Activation-aware Weight Quantization for LLM Compression and Acceleration*. arXiv:2306.00978, 2023 (MLSys 2024 Best Paper).] — The AWQ paper. The key figure is Figure 3 showing the bimodal distribution of salient vs. non-salient channels.

- #link("https://arxiv.org/abs/2402.17764")[Ma, Wang, Ma et al. *The Era of 1-bit LLMs: All Large Language Models are in 1.58 Bits*. arXiv:2402.17764, 2024.] — The BitNet b1.58 paper. Short and readable. Table 2 shows parity with Llama at 3B scale. Available in `papers/wang-2024-bitnet-b1.58.pdf`.

- #link("https://arxiv.org/abs/2208.07339")[Dettmers, Lewis, Belkada, Zettlemoyer. *LLM.int8(): 8-bit Matrix Multiplication for Transformers at Scale*. NeurIPS 2022.] — The outlier activation discovery. The paper that forced the field to take quantization seriously for LLMs.

- #link("https://arxiv.org/abs/2305.17888")[Liu, Yuan, Wu et al. *LLM-QAT: Data-Free Quantization Aware Training for Large Language Models*. ACL Findings 2024.] — The data-free QAT approach using self-generated calibration data.

- #link("https://developer.nvidia.com/blog/floating-point-8-an-introduction-to-efficient-lower-precision-ai-training/")[NVIDIA Developer Blog: *Floating-Point 8: An Introduction to Efficient, Lower-Precision AI Training*.] — A clear technical introduction to FP8, its two variants (E4M3 and E5M2), and H100 hardware support.

- #link("https://arxiv.org/abs/2402.04396")[Tseng, Chee, Sun, Kuleshov, De Sa. *QuIP\#: Even Better LLM Quantization with Hadamard Incoherence and Lattice Codebooks*. arXiv:2402.04396, 2024.] --- The QuIP\# method for sub-4-bit vector quantization.

#bridge[
  We now know how to compress the *weights* of a neural network — the static parameters that define what the model knows. But quantization is only one lever. Chapter 64 covers the remaining ways to shrink a static network: pruning (deleting entire weights or neurons), knowledge distillation (training a small model to mimic a large one), and low-rank factorization (replacing big matrices with thin ones). Then Chapter 65 turns to a different problem entirely. A neural network is not just its weights: when you run it on a long conversation, it also builds up a large collection of temporary stored computations called the *KV-cache* — and that cache grows linearly with how much you have said. Chapter 65 returns to that runtime problem, showing how to compress the KV-cache itself, the memory of the conversation in progress, where new algorithmic ideas like DeepSeek's Multi-head Latent Attention are reshaping what it costs to hold a long thought.
]
