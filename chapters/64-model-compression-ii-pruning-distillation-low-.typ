#import "../lib.typ": *
#import "@preview/cetz:0.4.2"

= Model Compression II: Pruning, Distillation, Low-Rank

#epigraph[
  The art of being wise is the art of knowing what to overlook.
][William James, _The Principles of Psychology_, 1890]

Here is a thought experiment. You have a language model with 7 billion weights (7,000,000,000 individual numbers, each requiring 16 bits of storage). Total: 14 gigabytes. You want to run it on a laptop with 8 GB of RAM and no fancy GPU. Chapter 63 showed you one path: quantize the weights from 16 bits down to 4 bits and you squeeze into 3.5 GB. But quantization is only one of three major levers available. This chapter covers the other two:

- *Pruning*: cut weights (or entire neurons, or whole layers) that are not doing much useful work, leaving a smaller, sparser model.
- *Knowledge distillation*: train a fresh, small model to *mimic* the behavior of the large one, transferring what the big model knows without copying its parameters.
- *Low-rank factorization and LoRA*: replace heavyweight weight matrices with products of two thin matrices, exploiting the mathematical fact that most weight matrices are "almost low-rank."

These three techniques are not competitors. A real production pipeline at Google, Meta, or Huawei often applies all three in sequence: prune, then distill, then quantize. The goal in every case is the same one that has run through this entire book: exploit redundancy. A trained neural network turns out to be extraordinarily redundant.

#recap[
  Chapter 39 introduced scalar quantization for DCT coefficients (JPEG). Chapter 63 extended that idea to neural network weights: GPTQ uses Hessian-based compensation to round weights to 4 bits; AWQ protects "salient" channels by rescaling before rounding. Both methods compress the *numbers that describe the model*. This chapter compresses the *structure* of the model itself: removing weights, layers, and parameters at the architectural level, not just rounding their values.
]

#objectives((
  "Explain the difference between unstructured, structured, and semi-structured pruning",
  "State the Lottery Ticket Hypothesis precisely and understand why it matters",
  "Walk through the SparseGPT algorithm step by step",
  "Explain why knowledge distillation works via soft probability targets",
  "Trace the idea from Hinton's 2015 paper to DeepSeek-R1's 2025 distilled models",
  "Understand why a weight matrix is often low-rank and what that means",
  "Explain the LoRA trick precisely, with the rank-decomposition equation",
  "Combine pruning, distillation, and LoRA in a single deployment pipeline",
))

== Pruning: Cutting the Fat

The word "pruning" comes from gardening. You trim branches that are not bearing fruit, and the remaining plant grows stronger and more efficiently. The same intuition applies to neural networks, and it dates back further than most people realize.

#history[
  The idea that neural networks are over-parameterized and can be thinned after training goes back at least to *Optimal Brain Damage* (LeCun, Denker, and Solla, NeurIPS 1990) and *Optimal Brain Surgeon* (Hassibi and Stork, NeurIPS 1993). Both methods used second-order information (the curvature of the loss) to identify which weights could be removed with the least damage. They were essentially impractical at the time: the Hessian of a network with even 10,000 parameters is enormous to compute. The algorithms were largely forgotten for two decades, then dramatically resurrected in the deep learning era when someone needed to fit a neural network onto a microcontroller.
]

=== Three Kinds of Pruning

Pruning approaches differ in *what* they remove. The distinction matters enormously for hardware:

*Unstructured pruning* sets individual weights to zero, regardless of their position. The resulting matrix is *sparse*: most entries are zero but the non-zero entries are scattered randomly. Unstructured pruning typically achieves the best accuracy-to-sparsity trade-off because it picks exactly the least-important weights. The problem: a matrix with 50% of its entries randomly zeroed is *not automatically faster* to multiply on a GPU. GPUs are built for dense matrix operations; randomly skipping entries means irregular memory access, which wastes the hardware. You need special sparse kernels to benefit, and these are hard to write and often not much faster than dense until sparsity reaches 90%+.

*Structured pruning* removes whole *structures*: an entire neuron (all inputs and outputs), an entire attention head, an entire layer. The pruned network has a smaller, but *dense*, weight matrix. A dense matrix multiply on a smaller matrix is a standard operation that runs fast on every GPU. The trade-off: structured pruning is coarser-grained, and you tend to need more total pruning to meet the same accuracy, because you cannot pick and choose exactly which individual weights matter.

*Semi-structured pruning* is a hardware-motivated compromise introduced with NVIDIA's Ampere architecture (A100 GPU, 2020). The GPU executes operations in tiles, and if you guarantee that *within every block of 4 consecutive weights, exactly 2 are non-zero*, the hardware can exploit this "2:4 sparsity" pattern directly, achieving roughly a 2× speedup with dedicated sparse tensor cores. It is less flexible than fully unstructured pruning but works on standard hardware.

#keyidea[
  The fundamental trade-off in pruning: *unstructured* sparsity is most accurate but rarely speeds up real hardware; *structured* sparsity slows down only in accuracy terms but translates directly into faster inference. Modern methods (SparseGPT, Wanda) target 2:4 semi-structured sparsity for this reason.
]

#fig([Three pruning regimes, illustrated on a 4×4 weight matrix. Stars mark removed weights.],
  cetz.canvas({
    import cetz.draw: *
    // Unstructured: random zeros
    let box_size = 0.7
    let colors_u = ((0,0),(1,2),(2,1),(3,0),(0,3),(2,3)) // pruned positions
    let colors_s = ((0,0),(0,1),(0,2),(0,3)) // pruned row
    let colors_24 = ((0,1),(1,0),(2,3),(3,2)) // 2:4 pattern

    // Title labels
    content((1.4, 3.5), box(width: 2.6cm, inset: 2pt, align(center, text(size: 8pt)[Unstructured])))
    content((5.4, 3.5), box(width: 2.6cm, inset: 2pt, align(center, text(size: 8pt)[Structured (row)])))
    content((9.4, 3.5), box(width: 2.6cm, inset: 2pt, align(center, text(size: 8pt)[Semi-structured 2:4])))

    // Draw three 4x4 grids
    for grid_x in (0, 4, 8) {
      for r in range(4) {
        for c in range(4) {
          let x = grid_x + c * box_size
          let y = r * box_size
          rect((x, y), (x + box_size, y + box_size), stroke: 0.5pt)
        }
      }
    }

    // Shade pruned cells - unstructured
    for (r, c) in colors_u {
      let x = 0 + c * box_size
      let y = r * box_size
      rect((x, y), (x + box_size, y + box_size), fill: rgb("#d3d3d3"), stroke: 0.5pt)
      content((x + box_size/2, y + box_size/2), text(size: 6pt)[✕])
    }

    // Shade pruned row - structured
    for c in range(4) {
      let x = 4 + c * box_size
      let y = 0 * box_size
      rect((x, y), (x + box_size, y + box_size), fill: rgb("#a0c4ff"), stroke: 0.5pt)
      content((x + box_size/2, y + box_size/2), text(size: 6pt)[✕])
    }

    // 2:4 pattern
    for (r, c) in colors_24 {
      let x = 8 + c * box_size
      let y = r * box_size
      rect((x, y), (x + box_size, y + box_size), fill: rgb("#b7e4c7"), stroke: 0.5pt)
      content((x + box_size/2, y + box_size/2), text(size: 6pt)[✕])
    }
  })
)

=== Magnitude Pruning: The Simple Baseline

The simplest pruning strategy is *magnitude pruning*: compute the absolute value of every weight, sort them, and set the bottom $k$% to zero. The assumption is that small weights contribute little to the network's output. For weights near zero, the output change from removing them is approximately $w times x approx 0 times x approx 0$.

This works surprisingly well for modest sparsity levels (20–40%). It fails badly at high sparsity (70%+) because weights that are currently small may have become small *because other weights compensate for them*. Remove both together and you have a problem. The magnitude alone does not tell you the importance of a weight in context.

A simple worked example: suppose a single neuron has weights $[0.01, 0.95, 0.03, 0.87]$ and the incoming activations are always $[100, 0.1, 0.05, 0.2]$. The weight $0.01$ looks tiny. But it multiplies an activation of $100$, giving a contribution of $1.0$. Meanwhile the weight $0.95$ multiplies an activation of $0.1$, contributing only $0.095$. Magnitude pruning would keep $0.95$ and remove $0.01$, which is exactly wrong. This is the same outlier-activation problem that bedeviled quantization in Chapter 63.

=== The Lottery Ticket Hypothesis

In 2019, MIT researchers Jonathan Frankle and Michael Carbin published a paper that changed how researchers think about pruning. Its core claim was audacious:

#definition("Lottery Ticket Hypothesis")[
  A randomly initialized neural network contains a small *subnetwork* (called the "winning ticket") such that, if that subnetwork is trained in isolation starting from its *original* (random) initialization, it can match the full network's accuracy in the same number of training steps.
]

The name comes from an analogy: among all the randomly initialized weights, you got "lucky" with some of them; they happen to start at values from which learning is efficient. These are the winning tickets. The full training run discovers which tickets win, but you don't need to keep the losers.

The implications are remarkable. They say: the big network you trained is not a monolithic thing. Hidden inside it is a small, trainable subnetwork. In principle, if you could find it *before* training, you would never need the big network at all. In practice, the ticket is found by training the big network first, then pruning, then verifying that the pruned subnetwork (*rewound to its original initialization*) trains to full accuracy from scratch.

#algo(
  name: "Iterative Magnitude Pruning (IMP): Lottery Ticket search",
  year: "2019",
  authors: "Jonathan Frankle and Michael Carbin (MIT CSAIL)",
  aim: "Find a sparse subnetwork (the 'winning ticket') that, when re-initialized to its original random values and trained alone, matches full-network accuracy.",
  complexity: "O(T × k) where T = full training time and k = number of pruning rounds; very expensive, since you train the full network k+1 times total.",
  strengths: "Reveals deep structure in trained networks; winning tickets at 90%+ sparsity found for small models; spurred huge follow-on work.",
  weaknesses: "Does not scale to large language models (you cannot afford to train GPT-sized networks k times); initialization rewind is impractical for pre-trained models; hard to prove winning tickets exist for very deep networks.",
  superseded: "As a deployment technique: largely replaced by SparseGPT/Wanda for LLMs. As a scientific hypothesis: still actively studied; 'late resetting' and 'linear mode connectivity' are 2022–2025 extensions.",
)[
  Frankle and Carbin found winning tickets at 10–20% of the original network size (80–90% sparsity) for MNIST and CIFAR-10 models. The same approach applied to larger ResNets and Transformers showed that winning tickets do exist, but finding them costs orders of magnitude more than the original training. The hypothesis is scientifically important but not a practical compression recipe for frontier LLMs.
]

The Lottery Ticket Hypothesis matters for this book because it provides the theoretical backbone of why pruning *can* work at all. The big network is wasteful by design: it carries thousands of "losing tickets" that never would have won. Training the big network is an expensive lottery draw. Pruning discards the losers. You are left with something that, in principle, could have been trained smaller from the start. You just didn't know which weights to keep until after training.

#checkpoint[What is the key difference between the Lottery Ticket finding and simply pruning after training?][The Lottery Ticket Hypothesis says the winning subnetwork can be *retrained from its original random initialization* and still reach full accuracy. Simple post-training pruning just removes weights from the already-trained model and does not reset them. The rewind-to-initialization step is what makes the hypothesis remarkable; it is also what makes it expensive to verify.]

=== SparseGPT: One-Shot LLM Pruning

For models with billions of parameters, iterative retraining is out of the question. You need to prune without retraining, the same "post-training" constraint we saw for quantization in Chapter 63.

*SparseGPT* (Frantar and Alistarh, ETH Zurich, 2023) solved this for transformer-scale models. It was the first method to prune a 175-billion-parameter model (OPT-175B) to 50% sparsity in a single pass, on a single GPU, in a matter of hours, with almost no accuracy loss.

The idea draws directly from Optimal Brain Surgeon (1993) and from the same Hessian-compensation trick that GPTQ used for quantization. The math is identical in structure; the connection is intentional and explicit in the paper.

#mathrecall[
  The *Hessian* $H$ is the matrix of second derivatives of the loss. It measures the *curvature* of the loss surface, telling you how sharply the error grows as you nudge each weight. We met it in Chapter 63: GPTQ uses $H = 2 X X^T$ (built from the layer's input activations $X$) and its inverse $H^(-1)$ to decide how to compensate the surviving weights when one is rounded or removed. A large curvature means "this weight is sensitive, change it carefully." SparseGPT reuses that exact machinery for pruning instead of rounding.
]

Here is the core insight. When you remove weight $w_q$ (set it to zero), the error in the layer's output is:

$ delta_"output" approx w_q times x_q $

where $x_q$ is the activation reaching that weight. To compensate, you can nudge the remaining weights in the same row by an amount determined by the Hessian inverse:

$ delta w_j = - (w_q) / (H^(-1)_(q q)) H^(-1)_(q j), quad j != q $

Read $H^(-1)_(q j)$ as "the entry in row $q$, column $j$ of the inverse Hessian." In words: the size of the nudge to a surviving weight $w_j$ is the removed weight $w_q$ scaled by how strongly the curvature couples positions $q$ and $j$. Weights whose computation was entangled with the deleted one get the biggest corrections; unrelated weights are barely touched. This is the same Optimal Brain Surgeon update that Hassibi and Stork derived in 1993. What was impractical in 1993 (computing $H^(-1)$ for a large network) is now feasible layer by layer, using the same trick as GPTQ: feed a small calibration dataset, compute $H = 2 X X^T$, invert it once, and then process all weights with the cached inverse.

#algo(
  name: "SparseGPT",
  year: "2023 (ICML 2023)",
  authors: "Elias Frantar and Dan Alistarh (ETH Zurich / IST Austria)",
  aim: "One-shot unstructured or semi-structured pruning of LLMs to 50–60% sparsity using Hessian-based weight compensation, without any retraining.",
  complexity: "O(d³) per weight matrix for Hessian inversion; linear passes over calibration data. A 175B model takes ~5 GPU-hours to prune.",
  strengths: "No retraining; 50% sparsity with <1% perplexity increase on large models; supports 2:4 semi-structured sparsity natively; same Hessian inverse reused across weight rows (efficient).",
  weaknesses: "Serial column-by-column processing; calibration data required; 2:4 sparsity pattern gives limited speedup without Ampere+ GPUs; unstructured sparsity rarely speeds up commodity hardware.",
  superseded: "Wanda (2023) offers a faster, Hessian-free approximation; SliceGPT (2024) and structural methods pursue structured removal instead.",
)[
  SparseGPT was co-developed with GPTQ by the same group and shares its core mathematical machinery. The authors explicitly frame both as instantiations of the same Optimal Brain Surgeon framework, adapted to the post-training, no-retraining setting. This is a pleasing example of old ideas (1993) becoming suddenly practical three decades later, once the hardware and the problem scale matched.
]

=== Wanda: Pruning Without the Hessian

SparseGPT's Hessian inversion is expensive. In 2024, *Wanda* (Mingjie Sun, Zhuang Liu, Anna Bair, and J. Zico Kolter, ICLR 2024) showed you can get almost the same result much more cheaply.

Wanda's pruning score for weight $w_(i j)$ is simply:

$ S_(i j) = abs(w_(i j)) times norm(X_j)_2 $

That is: the magnitude of the weight, times the $L_2$ norm of the corresponding input activation $X_j$ (averaged over a calibration batch). This is *not* a Hessian computation. It is a single forward pass to collect activations, followed by element-wise multiplication. No matrix inversion, no iterative solver.

Why does this work? The key insight from GPTQ's outlier analysis (Chapter 63): a small weight multiplied by a large activation is dangerous to remove. Wanda's score directly captures this interaction. It is the activation-aware saliency of AWQ, adapted for pruning instead of quantization.

The result: Wanda prunes 50% of weights with comparable accuracy to SparseGPT, in a fraction of the time, and supports both unstructured and 2:4 structured sparsity. For 2:4 sparsity on LLaMA-2-70B, Wanda matches SparseGPT's accuracy within measurement noise.

#gopython("NumPy Array Norms")[
  The *norm* of a vector is its "length": a single number summarizing the magnitudes of all its entries. The most common is the $L_2$ norm (Euclidean length):

  $ norm(v)_2 = sqrt(v_1^2 + v_2^2 + ... + v_n^2) $

  In NumPy you compute it as `np.linalg.norm(v)`. For a matrix of activations, `np.linalg.norm(X, axis=0)` gives the $L_2$ norm of each *column*, one number per input feature.

  ```python
  import numpy as np

  # Suppose activations X has shape (batch=4, features=3)
  X = np.array([[1.0, 100.0, 0.5],
                [0.9,  98.0, 0.3],
                [1.1, 102.0, 0.4],
                [0.8,  99.0, 0.6]])

  col_norms = np.linalg.norm(X, axis=0)
  print(col_norms)
  # Output: [1.80, 199.5, 0.83]  (the middle feature has huge norm - an outlier!)
  ```

  In Wanda, those column norms are multiplied by the weight magnitudes to produce the pruning score. The middle column would make even a tiny weight score high, keeping it alive.
]

A tiny worked Wanda example: suppose one row of a weight matrix is $W = [0.01, 0.50, 0.03, 0.80]$ and the activation norms are $norm(X)_2 = [90, 0.2, 0.1, 0.4]$. Wanda scores:

$S = [0.01 times 90, \ 0.50 times 0.2, \ 0.03 times 0.1, \ 0.80 times 0.4] = [0.90, \ 0.10, \ 0.003, \ 0.32]$

To reach 50% sparsity in this row, prune the two lowest-scoring weights: positions 2 and 3. The naive magnitude pruner would have kept position 2 because $0.50$ looks large, while removing position 1 because $0.01$ looks small - the exact opposite of what Wanda does.

#gopython("Wanda pruning score: toy implementation")[
  ```python
  import numpy as np

  def wanda_scores(W: np.ndarray, X: np.ndarray) -> np.ndarray:
      """
      W: weight matrix of shape (out_features, in_features)
      X: calibration activations of shape (batch, in_features)
      returns: score matrix same shape as W
      """
      # L2 norm of each input column across the calibration batch
      col_norms = np.linalg.norm(X, axis=0)  # shape: (in_features,)
      # Each row of W is multiplied element-wise by the column norms
      return np.abs(W) * col_norms[np.newaxis, :]

  def prune_50_percent(W: np.ndarray, scores: np.ndarray) -> np.ndarray:
      """Set the bottom 50% of weights (by score) to zero."""
      W_pruned = W.copy()
      threshold = np.percentile(scores, 50)
      W_pruned[scores < threshold] = 0.0
      return W_pruned

  # --- tiny self-test ---
  W = np.array([[0.01, 0.50, 0.03, 0.80]])
  X = np.array([[90.0, 0.2, 0.1, 0.4]] * 4)  # batch of 4 identical rows

  scores = wanda_scores(W, X)
  print("Scores:", scores)         # [[0.9, 0.1, 0.003, 0.32]]
  W_p = prune_50_percent(W, scores)
  print("Pruned:", W_p)            # [[0.01, 0.0, 0.0, 0.80]] - correct!
  ```
]

=== Structured Pruning: Removing Whole Neurons and Heads

Unstructured pruning, even with 2:4 patterns, requires special hardware support to translate into actual speedup. For general-purpose CPUs and older GPUs, *structured pruning* is more practical.

The most common structured targets in a transformer are:

- *Attention heads*: a transformer uses 32 or 64 parallel "attention heads" that each attend to different aspects of the input. Individual heads can be removed entirely after ranking them by importance (measured on a calibration set). Pruning 25–30% of heads typically costs less than 1% accuracy.
- *Feed-forward intermediate dimension*: the two feed-forward matrices in each transformer block have a large "intermediate" dimension (often 4× the model dimension). Reducing this dimension is a structured cut that immediately produces a smaller, faster matrix multiply.
- *Entire layers*: *SliceGPT* (2024, from Microsoft Research) removes entire weight columns and rows from matrices, effectively reducing the model's hidden dimension. The result is a model with the same number of layers but uniformly narrower, straightforward to run on hardware optimized for smaller dense matrices.

#aside[
  *LLM-Pruner* (Ma et al., NeurIPS 2023) extended structured pruning to dependencies. In a transformer, removing a neuron from one layer forces you to remove corresponding neurons in other layers (since they feed the same residual stream). LLM-Pruner builds a dependency graph of the entire model, identifies groups of coupled weights, and estimates each group's importance jointly. The result: 20% structured pruning of LLaMA with a single GPU-day of recovery fine-tuning.
]

== Knowledge Distillation: Teach a Small Student

Pruning asks: which parts of the big model can we remove? Distillation asks a different question: instead of shrinking the big model, can we *teach* a fresh, smaller model to behave like the big one?

The key insight is subtle. When a model classifies an image of a cat, it does not just output "cat." It outputs a probability distribution over all possible classes: "cat: 97%, lynx: 1.5%, fox: 0.8%, ..." Those near-zero probabilities on wrong classes are surprisingly informative. They reveal the model's internal notion of *similarity*. The small probability of "lynx" tells the student that cats are somewhat like lynxes. A hard label ("cat: 1, everything else: 0") discards that information.

#history[
  *Geoffrey Hinton, Oriol Vinyals, and Jeff Dean (2015)* published "Distilling the Knowledge in a Neural Network" while at Google. The paper is remarkably short (9 pages) and remarkably clear. Hinton had been developing the idea since at least 2006 under the name "Dark Knowledge." The soft probabilities he called "dark knowledge" are information hidden in the near-zero outputs of a trained model that hard labels cannot carry. His experiments showed that a small model trained on soft targets outperformed the same architecture trained on hard labels, sometimes by large margins. The paper now has over 25,000 citations and has become a standard reference for modern model deployment.
]

=== The Distillation Loss

Formally, suppose the teacher produces logits $z^T$ (the raw scores before softmax) and the student produces logits $z^S$. The *temperature* $T$ (not to be confused with the teacher model T) softens both distributions:

$ p_i^T = exp(z_i^T / tau) / (sum_j exp(z_j^T / tau)), quad p_i^S = exp(z_i^S / tau) / (sum_j exp(z_j^S / tau)) $

#gomaths("Temperature in a Softmax")[
  *Softmax* converts a vector of raw scores into a probability distribution. Each entry $z_i$ becomes:

  $ "softmax"(z)_i = exp(z_i) / (sum_j exp(z_j)) $

  The *temperature* $tau$ divides all scores before softmax. At $tau = 1$, this is standard softmax. At $tau > 1$, the resulting distribution is *flatter* (softer): small probabilities become a little larger and large probabilities become a little smaller. At $tau arrow 0$, the distribution collapses to a hard "1 for the top class, 0 for everything else."

  Example: scores $z = [4, 2, 1]$.
  - $tau = 1$: probs $approx [0.84, 0.11, 0.04]$, confidently "class 0."
  - $tau = 4$: probs $approx [0.49, 0.29, 0.22]$, much softer; classes 1 and 2 get meaningful probability.

  Distillation uses $tau = 4$–$10$ so the tiny probabilities on "wrong" classes become large enough to carry a gradient signal to the student.
]

#gomaths("Cross-Entropy: Measuring the Gap Between Distributions")[
  *Cross-entropy* measures how surprised one probability distribution is by samples from another. If the true distribution is $p$ and your model predicts $q$, the cross-entropy is:

  $ cal(L)_"CE"(p, q) = - sum_i p_i log_2 q_i $

  Intuition: $-log_2 q_i$ is the codelength (in bits) you would assign to class $i$ if you used distribution $q$ as your codebook. Cross-entropy is the *average* codelength when samples actually come from $p$. Minimizing cross-entropy means making the model's predictions $q$ as close as possible to the truth $p$.

  When $p$ is a one-hot hard label ($p_"cat" = 1$, all others 0), the sum collapses to a single term: $cal(L)_"CE" = -log_2 q_"cat"$. The loss is simply how many bits your model wastes on the wrong answer.

  When $p$ is a soft distribution (as in distillation), every non-zero class contributes. Getting the small probabilities right (the "lynx: 0.04") lowers the loss just as much as getting the top class right.
]

The distillation loss is a mixture of two terms:

$ cal(L)_"distill" = alpha dot cal(L)_"CE"(p^S_tau, p^T_tau) + (1 - alpha) dot cal(L)_"CE"(p^S_1, y) $

where $cal(L)_"CE"$ is cross-entropy, $p^S_tau$ and $p^T_tau$ are the student's and teacher's temperature-softened distributions, $y$ is the hard one-hot ground-truth label, and $alpha$ (typically 0.9) controls the trade-off. The first term teaches the student to *match the teacher's output distribution*. The second term keeps the student anchored to the true labels.

A critical detail: the teacher-matching cross-entropy must be scaled by $tau^2$ to keep gradients at the same magnitude as for the hard-label term. (This is because dividing by $tau$ inside softmax makes the soft probabilities smaller by a factor of $tau$, which reduces the gradient by $tau^2$.) Hinton 2015 is explicit about this and most implementations include the rescaling.

#algo(
  name: "Knowledge Distillation (KD)",
  year: "2015",
  authors: "Geoffrey Hinton, Oriol Vinyals, Jeff Dean (Google Brain)",
  aim: "Train a small 'student' model to match the soft probability outputs of a large 'teacher' model, transferring 'dark knowledge' that hard labels cannot carry.",
  complexity: "Student training cost, plus teacher inference cost for each training batch (teacher runs forward-only, so roughly 2× student compute). No teacher backward pass required.",
  strengths: "Can close most of the accuracy gap between student and teacher; works without the teacher's training data (black-box distillation); the student architecture is unconstrained, so any smaller model works; widely deployed (every major tech company uses some form of this).",
  weaknesses: "Requires access to either the teacher's logits or its outputs; very large teacher–student size gaps may not distill well (the 'capacity gap problem'); temperature tuning is finicky; teacher must be available at training time.",
  superseded: "Still the dominant paradigm; extended to LLMs by MiniLLM (2024), DistiLLM (2024), DeepSeek-R1 distillation (2025), and many others.",
)[
  The original paper demonstrated distillation on acoustic models for speech recognition (where it was originally developed by Hinton's group) and on MNIST. The acoustic model experiments showed that an ensemble of 10 teacher models could be distilled into a single model that outperformed any individual member of the ensemble. Compression, in that case, actually *exceeded* the teacher by concentrating ensemble knowledge.
]

=== Why Soft Targets Work: An Intuition

Consider a model classifying handwritten digits (MNIST). When it sees a "7", the hard label says: "7: 1, everything else: 0." The teacher's soft output might say: "7: 0.92, 1: 0.04, 9: 0.03, 4: 0.01." That $0.04$ on "1" is not noise. It is the teacher's learned knowledge that 7s and 1s look similar, both having vertical strokes. The student trained on soft targets learns this similarity implicitly. The student trained on hard targets does not.

More formally: the soft targets provide a much richer training signal per example. A hard label has essentially 1 bit of useful information (which class). A soft probability vector over 1000 classes has up to $log_2(1000) approx 10$ bits. You need many fewer training examples to converge when each carries 10 bits of signal versus 1 bit.

#keyidea[
  Soft targets are a compressed representation of the teacher's world-model. The near-zero probabilities encode the teacher's similarity judgments: which concepts are close, which are far. Distillation is, literally, compression of knowledge.
]

=== Feature-Level Distillation

Hinton's original formulation matched only the final output layer. Later work realized you could match *intermediate layer activations* too: the features, attention patterns, or hidden states at each transformer layer.

*FitNets* (2015) trained a thin, deep student to mimic not just the teacher's output but its intermediate representations. *TinyBERT* (Jiao et al., NeurIPS 2020) distilled BERT by matching attention matrices and hidden states at corresponding layers: a 4-layer student matching a 12-layer teacher's representations at every other layer. The result: 7.5× smaller, 9.4× faster, and retaining 96.8% of BERT's performance on the GLUE benchmark. TinyBERT showed that for transformers, matching intermediate attention patterns is far more efficient than matching only final outputs.

=== Distillation for Reasoning: DeepSeek-R1

The most striking demonstration of distillation's power in 2024–2025 was *DeepSeek-R1* (released January 2025 by Chinese AI company DeepSeek). The story:

DeepSeek trained a large reasoning model (671 billion parameters, mixture-of-experts architecture, meaning only a fraction of the weights activate per token) using large-scale reinforcement learning with a specialized reward for mathematical and logical reasoning. This model (DeepSeek-R1) achieved performance competitive with OpenAI's o1 model.

They then distilled it: they generated *800,000 examples* of the teacher's chain-of-thought reasoning (not just final answers, but the full "think step by step" process) and used that data to fine-tune existing open models (Qwen and LLaMA) via standard supervised fine-tuning. No RL was needed for the students. The result: DeepSeek-R1-Distill-Qwen-7B (7 billion parameters, not 671 billion) matched or exceeded the performance of much larger models on most reasoning benchmarks, including GPT-4o and Claude 3.5 Sonnet, on mathematical reasoning tasks.

This is distillation as *reasoning transfer*: the student does not just copy output probabilities, it learns to *think like* the teacher by imitating the teacher's internal reasoning traces.

#pitfall[
  Distillation is not magic. The student model has a limited *capacity*, a maximum amount of information it can store, determined by its number of parameters and architecture. If the teacher is much larger than the student, distillation will transfer only the parts of the teacher's knowledge that fit. For mathematical reasoning, this turns out to be a surprisingly large fraction. For tasks requiring diverse world knowledge distributed across many rare facts, the capacity gap bites hard.
]

#checkpoint[A student model is trained with $tau = 8$ and $alpha = 0.9$. What do those numbers mean in practice?][Temperature $tau = 8$ means the teacher's probability distribution is softened significantly before the student is trained to match it: near-zero probabilities on non-target classes are amplified, bringing class-similarity information into view. $alpha = 0.9$ means 90% of the loss comes from matching the teacher's soft distribution and only 10% from matching the hard ground-truth labels, so training is heavily teacher-guided.]

== Low-Rank Factorization and LoRA

Here is a fact about matrices that seems unrelated to neural networks but turns out to be central: most large matrices in the real world are *approximately low-rank*. They can be closely approximated by the product of two much thinner matrices.

=== What "Rank" Means

#gomaths("Matrix Rank and SVD")[
  The *rank* of a matrix $W$ (with shape $m times n$) is the number of truly independent directions it encodes. A matrix of rank $r$ can be *exactly* written as:

  $ W = U S V^T $

  where $U$ has shape $m times r$, $S$ is an $r times r$ diagonal matrix of *singular values* $sigma_1 >= sigma_2 >= ... >= sigma_r > 0$, and $V^T$ has shape $r times n$. This is the *Singular Value Decomposition (SVD)*.

  The singular values measure how much each direction "matters." If $sigma_1 >> sigma_2 >> ... >> sigma_r$, the matrix is dominated by its first few directions and the rest are negligible.

  The *low-rank approximation* keeps only the top $k < r$ singular values and sets the rest to zero:

  $ W approx U_k S_k V_k^T = A B $

  where $A = U_k S_k^(1/2)$ has shape $m times k$ and $B = S_k^(1/2) V_k^T$ has shape $k times n$.

  Storage comparison: full matrix $W$ costs $m times n$ numbers. Low-rank approximation costs $m times k + k times n = k(m+n)$ numbers. For a $4096 times 4096$ weight matrix and rank $k = 8$:
  - Full: $4096 times 4096 = 16,777,216$ numbers.
  - Rank-8: $8 times (4096 + 4096) = 65,536$ numbers. That is a *256× reduction*.
]

Why would a trained weight matrix be low-rank? The intuition: during training, the model solves a task (predict the next word, classify an image). The task has some effective dimensionality, the number of truly independent factors that matter for solving it. If the task has $k$ important factors but the weight matrix has $4096$ dimensions, the matrix only needs rank $k$ to express all the relevant computation. The remaining $4096 - k$ dimensions fill with near-zero singular values, mathematical noise.

Empirically, for large language models, the weight matrices in attention and feed-forward layers do have rapidly decaying singular values. Cutting off the bottom 80–90% of singular values often changes the layer output by less than 1%.

=== Classic Low-Rank Compression

The direct application: perform SVD on every weight matrix, keep only the top $k$ singular values, and replace the original matrix with two smaller matrices $A$ and $B$. This was explored as early as 2013 for speech recognition models (Xue et al., ICASSP 2013) and generalized to many neural network architectures in the years that followed.

The challenge: choosing $k$ per layer (different layers may have different effective ranks) and the accuracy loss from discarding singular values. A well-known result (Eckart–Young theorem) says the rank-$k$ approximation by SVD is the *best possible* rank-$k$ approximation in the _Frobenius norm_ sense (the Frobenius norm is just the $L_2$ norm of a matrix flattened into one long vector, $norm(W)_F = sqrt(sum_(i,j) w_(i j)^2)$, so "small Frobenius distance" means "the two matrices differ by little, entry by entry"). But "best approximation of the weight matrix" is not the same as "best approximation of the model's behavior": you are minimizing the wrong objective.

=== LoRA: Low-Rank Adaptation

The most influential low-rank method of the last few years is not about compressing a *trained* model; it is about *fine-tuning* a pre-trained model efficiently. But the insight connects directly to compression.

*LoRA (Low-Rank Adaptation)* was published by Edward Hu, Yelong Shen, Phillip Wallis, Zeyuan Allen-Zhu, Yuanzhi Li, Shean Wang, Lu Wang, and Weizhu Chen at Microsoft in 2021 (published ICLR 2022). The premise: when you fine-tune a large pre-trained model on a new task, the *change* in the weights is approximately low-rank. You do not need to update all 7 billion parameters; you just need to update a small low-rank perturbation on top of the frozen pre-trained weights.

The mechanism. Take a weight matrix $W_0 in RR^(m times n)$ from the pre-trained model. Instead of updating $W_0$ directly (which requires $m times n$ gradient computations and $m times n$ stored parameters), freeze $W_0$ and introduce two small trainable matrices $A in RR^(r times n)$ and $B in RR^(m times r)$, where $r << min(m, n)$. The adapted weight is:

$ W = W_0 + B A $

$B A$ is a rank-$r$ matrix (at most). Only $A$ and $B$ are trained; $W_0$ is frozen. The forward pass uses $W x = W_0 x + B A x$. Since both $W_0 x$ and $A x$ then $B (A x)$ can be computed separately and added:

- Compute $W_0 x$ (frozen, no gradient).
- Compute $h = A x$ (small: $r times n$ matrix times $n$-vector → $r$-vector).
- Compute $B h$ (small: $m times r$ matrix times $r$-vector → $m$-vector).
- Output: $W_0 x + B h$.

The number of trainable parameters: $r times n + m times r = r(m + n)$. For GPT-3 ($m = n = 12288$, $r = 4$): $4 times (12288 + 12288) = 98,304$ parameters per weight matrix, versus $12288^2 = 150,994,944$ for full fine-tuning. That is a 1536× reduction in trainable parameters.

#algo(
  name: "LoRA",
  year: "2022 (ICLR)",
  authors: "Edward Hu, Yelong Shen, Phillip Wallis, Zeyuan Allen-Zhu, Yuanzhi Li, Shean Wang, Lu Wang, Weizhu Chen (Microsoft Research)",
  aim: "Efficient fine-tuning of large pre-trained models by learning only a low-rank perturbation $B A$ to each weight matrix, keeping the original weights frozen.",
  complexity: "Training: O(r) per weight matrix instead of O(m×n); inference: zero overhead if B and A are merged into W₀ before deployment.",
  strengths: "Dramatic reduction in fine-tuning parameters (1000× for r=4); no inference overhead after merging; multiple fine-tuned variants can coexist on the same frozen base; memory-efficient; enables fine-tuning on single GPUs.",
  weaknesses: "Does not reduce the size of the deployed base model; the rank r must be chosen (too low loses accuracy; too high negates the savings); may not capture fine-tuning changes of very high rank; limited to modifying existing weight matrices.",
  superseded: "Extended by QLoRA (quantize base + LoRA, 2023), AdaLoRA (adaptive rank, 2023), DoRA (weight decomposition, 2024), GaLore (gradient low-rank projection, 2024).",
)[
  LoRA was motivated by the observation that the weight update matrices during fine-tuning of GPT-3-scale models have very low _stable rank_: a soft, noise-tolerant count of how many singular values really matter, equal to the ratio of the squared Frobenius norm (sum of all squared singular values) to the squared largest singular value. A stable rank of, say, 3 means the update is effectively rank-3 even if technically full-rank. The empirical finding that $r = 4$ or $r = 8$ suffices for most fine-tuning tasks, while capturing nearly all the task-relevant adaptation, is the paper's central experimental result. LoRA is now the standard method for fine-tuning almost every open language model.
]

#fig([LoRA architecture. The frozen pretrained weight $W_0$ (grey) handles the main computation. Two small trainable matrices $A$ and $B$ add a low-rank correction $B A x$ to the output. After fine-tuning, $B A$ is merged into $W_0$ for zero inference overhead.],
  cetz.canvas({
    import cetz.draw: *

    // Input vector
    content((-1.5, 1.0), text(size: 8pt)[$x$])
    line((-1.2, 1.0), (-0.2, 1.0), mark: (end: ">"))

    // W_0 block (big, frozen, grey)
    rect((0, 0), (2, 2), fill: rgb("#d3d3d3"), stroke: 1pt)
    content((1, 1), box(width: 1.6cm, inset: 2pt, align(center, text(size: 8pt, fill: rgb("#555555"))[$W_0$ (frozen)])))

    // Lower branch: A then B
    rect((0, -1.8), (1.2, -1.0), fill: rgb("#b7e4c7"), stroke: 1pt)
    content((0.6, -1.4), box(width: 1.0cm, inset: 1pt, align(center, text(size: 7pt)[$A$ ($r,n$)])))
    rect((1.4, -1.8), (2.2, -1.0), fill: rgb("#aed6f1"), stroke: 1pt)
    content((1.8, -1.4), box(width: 0.6cm, inset: 1pt, align(center, text(size: 7pt)[$B$ ($m,r$)])))

    // Lines
    line((-0.2, 1.0), (-0.2, -1.4), stroke: 0.5pt)
    line((-0.2, -1.4), (0, -1.4), mark: (end: ">"), stroke: 0.5pt)
    line((1.2, -1.4), (1.4, -1.4), mark: (end: ">"), stroke: 0.5pt)

    // Sum circle
    circle((3.2, 1.0), radius: 0.2, stroke: 1pt)
    content((3.2, 1.0), text(size: 9pt)[$+$])

    // Connect W_0 output to sum
    line((2.0, 1.0), (3.0, 1.0), mark: (end: ">"))
    // Connect B output to sum
    line((2.2, -1.4), (3.2, -1.4), stroke: 0.5pt)
    line((3.2, -1.4), (3.2, 0.8), mark: (end: ">"), stroke: 0.5pt)

    // Output
    line((3.4, 1.0), (4.4, 1.0), mark: (end: ">"))
    content((4.6, 1.0), text(size: 8pt)[$y$])

    // Alpha label
    content((3.2, -1.8), text(size: 7pt)[scaled by $alpha \/ r$])
  })
)

=== QLoRA: Quantize the Base, LoRA the Adapters

*QLoRA* (Dettmers, Pagnoni, Holtzman, Zettlemoyer, University of Washington, NeurIPS 2023) combined two ideas: quantize the frozen base model to 4-bit (NF4 format, a 4-bit data type optimized for normally distributed weights) and then apply LoRA adapters on top in 16-bit precision.

The result was startling: you could fine-tune a 65-billion-parameter model on a *single consumer GPU with 48 GB of VRAM*. Previously this required at least 780 GB (10 × A100 GPUs). QLoRA did it in 24 hours. The quality was comparable to full float16 fine-tuning.

QLoRA also introduced a key trick called *double quantization*: quantize the quantization constants themselves (the scale factors for each group of 64 weights) to save additional memory. And *paged optimizers*: when GPU memory fills up, offload optimizer states to CPU RAM and page them back in as needed, using the same memory-paging mechanism as a computer's virtual memory system.

QLoRA made personal fine-tuning of frontier-class models a reality. It is now the standard first choice whenever you want to adapt a large open model to a specialized task on limited hardware.

=== GaLore: Gradient Low-Rank Projection

A 2024 development worth knowing: *GaLore* (Zhao et al., ICML 2024) extends the low-rank insight from *weight updates* to *gradients*. Recall from Chapter 56 that training adjusts each weight by following its _gradient_ (the slope of the loss). Modern training does not use the raw gradient: the standard *Adam* optimizer keeps two extra running averages per weight (a smoothed gradient for "momentum" and a smoothed squared gradient for its "second moment") to take steadier steps. Storing the gradient plus this optimizer state costs 8–12 bytes per parameter; for a 7B model, that is 56–84 GB just for optimizer state. GaLore projects the gradient matrix into a low-rank subspace (using a periodically updated SVD basis) before accumulating into the optimizer state, reducing optimizer memory by 4–8× with almost no accuracy loss.

GaLore is a genuine compression of the *training process*, not just the deployed model.

== Combining the Three: The Production Pipeline

In practice, frontier deployment teams use all three methods in sequence:

1. *Start with the pre-trained model* (e.g., LLaMA-3 70B, float16, 140 GB).
2. *Distill* into a smaller architecture (e.g., 7B), using the large model to generate soft labels for fine-tuning data (or using chain-of-thought traces, as DeepSeek-R1 did).
3. *Prune* the distilled model: apply SparseGPT or Wanda to reach 50% sparsity in attention and feed-forward weights.
4. *Quantize* to W4A16 using AWQ, bringing each weight to 4 bits.
5. *Deploy* with LoRA slots available: ship the quantized model + hooks to load task-specific LoRA adapters at inference time, switching tasks without reloading the base model.

The total compression from step 1 to step 5: $140 "GB" arrow.r$ (7/70 from distillation) $times$ (2/4 from quantization) $times$ (×0.5 from pruning weight only sparsity) $approx 140 times 0.1 times 0.5 times 0.5 approx 3.5 "GB"$. Fits in a phone.

This is not science fiction. As of 2025, the MLC AI group ships exactly this kind of pipeline (WebLLM, MLC-LLM) for running 7B models in a browser using WebGPU, and on Android phones using Vulkan.

#scoreboard(caption: "Weight of a 7B language model through the compression pipeline",
  [Stage], [Method], [Size (approx.)], [Relative to original],
  [Pre-trained float16], [-], [14 GB], [1x],
  [Post quantization INT4], [AWQ / GPTQ (Ch. 63)], [3.5 GB], [4×],
  [Post pruning 50%], [Wanda / SparseGPT], [3.5 GB (sparse)], [4× (storage same, compute ½)],
  [Distilled 7B from 70B], [KD soft targets], [14 GB float16], [5–10× vs. 70B teacher],
  [Distilled + INT4], [KD + AWQ], [3.5 GB], [20–40× vs. 70B teacher],
)

#takeaways((
  "Pruning removes weights (unstructured) or entire structures (structured) from a trained network. Structured pruning gives real hardware speedup; unstructured pruning needs special sparse kernels.",
  "The Lottery Ticket Hypothesis says every large network hides a small trainable subnetwork. It is scientifically important but too expensive to apply to LLMs directly.",
  "SparseGPT and Wanda prune LLMs to 50% sparsity in one pass without retraining, using Hessian compensation and activation-weighted magnitude respectively.",
  "Knowledge distillation trains a small student on the large teacher's soft probability outputs. Soft targets carry 'dark knowledge' (similarity structure) that hard labels discard.",
  "Temperature τ > 1 in softmax softens the teacher's distribution, amplifying near-zero probabilities so the student can learn from them.",
  "DeepSeek-R1 (2025) demonstrated chain-of-thought distillation: a 7B student matched 671B teacher performance on reasoning tasks by imitating the teacher's full thought traces.",
  "Most weight matrices in large models are approximately low-rank: their singular values decay rapidly, so they can be approximated by the product of two thin matrices.",
  "LoRA freezes pre-trained weights and learns a low-rank perturbation BA (rank r ≪ min(m,n)) for efficient fine-tuning, reducing trainable parameters by 100–1000×.",
  "QLoRA combines 4-bit quantization of the frozen base with 16-bit LoRA adapters, enabling fine-tuning of 65B models on a single consumer GPU.",
  "Production pipelines combine distillation, pruning, quantization, and LoRA in sequence to achieve 20–40× compression of frontier models for phone deployment.",
))

== Exercises

#exercise("64.1", 1)[
  A language model outputs logits $z = [3.0, 1.0, 0.0, -1.0]$ for classes A, B, C, D. Compute the standard softmax ($tau = 1$) and the temperature-softened softmax at $tau = 3$. Verify that the sum of probabilities is 1 in each case. What happens to the probability of the least-likely class (D) as temperature increases?
]
#solution("64.1")[
  Standard softmax ($tau = 1$): Compute $e^{3.0} = 20.09$, $e^{1.0} = 2.72$, $e^{0.0} = 1.00$, $e^{-1.0} = 0.37$. Sum = $24.18$. Probabilities: A = $0.831$, B = $0.112$, C = $0.041$, D = $0.015$.

  Temperature $tau = 3$: Divide logits by 3 first: $[1.0, 0.333, 0.0, -0.333]$. $e^{1.0} = 2.718$, $e^{0.333} = 1.395$, $e^0 = 1.000$, $e^{-0.333} = 0.717$. Sum = $5.830$. Probabilities: A = $0.466$, B = $0.239$, C = $0.172$, D = $0.123$.

  As temperature increases, D's probability rises from 1.5% to 12.3%, a substantial relative increase. This amplification of near-zero probabilities is exactly what makes soft targets useful for distillation.
]

#exercise("64.2", 1)[
  A weight row is $W = [0.02, -0.60, 0.01, 0.45]$ and calibration activation norms are $norm(X)_2 = [80, 0.3, 50, 0.5]$. Compute Wanda scores for each weight. Which weights would be pruned to achieve 50% sparsity in this row?
]
#solution("64.2")[
  Wanda scores: $abs(W) times norm(X)_2$:
  - Position 0: $0.02 times 80 = 1.60$
  - Position 1: $0.60 times 0.3 = 0.18$
  - Position 2: $0.01 times 50 = 0.50$
  - Position 3: $0.45 times 0.5 = 0.225$

  Sorted: 1.60, 0.50, 0.225, 0.18. For 50% sparsity, prune the two lowest-scoring: positions 1 (score 0.18) and 3 (score 0.225). Note: naive magnitude pruning would prune positions 0 and 2 (magnitudes 0.02 and 0.01), keeping the weights that multiply tiny activations while discarding those multiplied by activations of magnitude 80 and 50 - exactly the wrong call.
]

#exercise("64.3", 2)[
  A weight matrix $W$ has shape $1024 times 1024$. You apply a rank-$r$ approximation $W approx A B$ where $A in RR^(1024 times r)$ and $B in RR^(r times 1024)$.

  (a) How many numbers does the full matrix store? How many do the two factor matrices store?

  (b) For what value of $r$ does the factorization use exactly half the storage of the original?

  (c) At $r = 4$, what fraction of the original storage is used? Express as a percentage.
]
#solution("64.3")[
  (a) Full matrix: $1024 times 1024 = 1,048,576$ numbers. Factor matrices: $1024 times r + r times 1024 = 2048 r$ numbers.

  (b) Set $2048 r = 1,048,576 / 2 = 524,288$. So $r = 524,288 / 2048 = 256$. At rank 256, you use exactly half the storage.

  (c) At $r = 4$: $2048 times 4 = 8,192$ numbers. Fraction: $8,192 / 1,048,576 approx 0.0078 = 0.78%$. Less than 1% of the original storage!
]

#exercise("64.4", 2)[
  Explain in your own words why knowledge distillation often produces a student that is *better* than a student trained directly on the hard labels, even though both see the same raw training data. Your explanation should mention the concept of "dark knowledge" and the information content of soft versus hard targets.
]
#solution("64.4")[
  Hard labels convey only which class is correct: "cat: 1, everything else: 0." They carry roughly 1 bit of information per example (which class among N). Soft targets from a trained teacher convey the teacher's entire probability distribution over all classes: "cat: 0.92, lynx: 0.04, fox: 0.02, ..." These near-zero probabilities on wrong classes are "dark knowledge": the teacher's learned judgment that cats somewhat resemble lynxes (both have vertical ears and a pointed face) but not chairs. This similarity structure is invisible in the hard label. Training on soft targets, the student learns not just "this is a cat" but "cats are like lynxes but unlike chairs," a richer world model packed into each training example. The effective information per example rises from ~1 bit (hard label) toward $log_2 N$ bits (full soft distribution over N classes), which is why fewer examples suffice to train a capable student.
]

#exercise("64.5", 2)[
  The Lottery Ticket Hypothesis claims that within a large trained network there exists a sparse subnetwork that, when trained from the original random initialization, matches the full network's accuracy. Why can this finding not be directly used as a practical compression recipe for large language models? What would need to be true for it to become practical?
]
#solution("64.5")[
  The Lottery Ticket procedure requires: (1) train the full network to convergence, (2) prune the trained weights by magnitude, (3) reset remaining weights to their original random initialization, (4) train the pruned subnetwork again. For a model like GPT-3 (175B parameters), steps 1 and 4 each cost millions of GPU-hours and millions of dollars. Step 3 requires having saved the original random initialization, which is impractical for pre-trained models released without their checkpoints. The method scales poorly: winning tickets found for CIFAR-10 (a tiny dataset) do not transfer to ImageNet without modification; it is not clear whether large transformer architectures have winning tickets at the same sparsity ratios as small networks. For it to become practical, we would need either: (a) a way to find the winning ticket without training the full network (a lottery-ticket "oracle"), or (b) mathematical guarantees that translate the hypothesis into a polynomial-time algorithm for identifying the right subnetwork.
]

#exercise("64.6", 3)[
  You are deploying a 13B-parameter language model to run on a phone with 6 GB of RAM (available for the model). The base model is float16. Design a compression pipeline using at least three of the techniques from this chapter (quantization from Chapter 63 counts as one), and estimate the final model size. State your assumptions clearly and identify the biggest uncertainty in your estimate.
]
#solution("64.6")[
  One valid pipeline:
  1. *Knowledge distillation* from a 70B teacher: train a 13B student on soft targets from the teacher's logits on a 2-billion-token dataset. This is the most expensive step but preserves quality. No size change yet: 13B × 2 bytes = 26 GB.
  2. *4-bit quantization* (AWQ or GPTQ): compress weights from float16 to INT4. Storage: 13B × 0.5 bytes = 6.5 GB. But we need to store quantization constants (one float16 scale per 128 weights): adds ~100 MB. Still too large.
  3. *Structured pruning* (remove 20% of attention heads + reduce FFN intermediate dimension by 20%): removes roughly 20% of parameters. New size: 6.5 × 0.8 ≈ 5.2 GB.
  4. After merging and sparse representation, target ≈ 5 GB, within the 6 GB budget.

  Biggest uncertainty: the accuracy of the distilled 13B model relative to the 70B teacher. Distillation closes much of the teacher–student gap for instruction-following tasks, but may lose 5–15% relative accuracy on specialized domains. The pruning step adds another 1–3% accuracy loss. The final model may run at 85–92% of the original teacher's quality, which is acceptable for most phone use-cases.
]

== Further Reading

#link("https://arxiv.org/abs/1803.03635")[Frankle and Carbin, "The Lottery Ticket Hypothesis: Finding Sparse, Trainable Neural Networks," ICLR 2019]. The original ticket paper; clear, concise, and still well worth reading in full.

#link("https://arxiv.org/abs/2301.00774")[Frantar and Alistarh, "SparseGPT: Massive Language Models Can Be Accurately Pruned in One Shot," ICML 2023]. Extends Optimal Brain Surgeon to trillion-parameter scale; the mathematical connection to GPTQ is made explicit.

#link("https://arxiv.org/abs/2306.11695")[Sun et al., "A Simple and Effective Pruning Approach for Large Language Models (Wanda)," ICLR 2024]. Shows that activation-weighted magnitude suffices; a clean and reproducible result.

#link("https://arxiv.org/abs/1503.02531")[Hinton, Vinyals, and Dean, "Distilling the Knowledge in a Neural Network," NeurIPS 2015 workshop]. The foundational distillation paper; 9 pages, extremely readable; the temperature scaling derivation is in the appendix.

#link("https://arxiv.org/abs/2106.09685")[Hu et al., "LoRA: Low-Rank Adaptation of Large Language Models," ICLR 2022]. The LoRA paper; includes the stable-rank analysis that motivates why $r = 4$ suffices.

#link("https://arxiv.org/abs/2305.14314")[Dettmers et al., "QLoRA: Efficient Finetuning of Quantized LLMs," NeurIPS 2023]. QLoRA; the double-quantization and paged-optimizer tricks are in Section 3.

#link("https://arxiv.org/abs/2501.12948")[DeepSeek-AI, "DeepSeek-R1: Incentivizing Reasoning Capability in LLMs via Reinforcement Learning," January 2025]. Describes the teacher model and the distillation procedure that produced the R1-Distill series.

#link("https://arxiv.org/abs/2212.10559")[Ma et al., "LLM-Pruner: On the Structural Pruning of Large Language Models," NeurIPS 2023]. The dependency-graph approach to structured pruning; includes the recovery fine-tuning pipeline.

#bridge[
  We have now exhausted the three classical levers for compressing the *model weights*: quantization (Chapter 63), pruning, distillation, and low-rank compression (this chapter). But there is a fourth place where memory explodes at inference time: the *KV-cache*, the stored key and value vectors for every token in the model's context window. A model with a 128,000-token context window and 32 layers can accumulate gigabytes of KV-cache for a single conversation. Chapter 65 opens this new front: eviction strategies (dropping low-attention tokens), quantized caches, DeepSeek's Multi-head Latent Attention architecture (which bakes cache compression into the model itself), and the 2025–2026 vector-quantization frontier for embedding spaces.
]
