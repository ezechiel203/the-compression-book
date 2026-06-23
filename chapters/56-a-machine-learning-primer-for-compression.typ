#import "../lib.typ": *
#import "@preview/cetz:0.4.2"

= A Machine-Learning Primer for Compression

#epigraph[We wanted flying cars; instead we got a function that, shown enough examples, learns to round off the world.][a paraphrase, with apologies, of a famous Silicon Valley lament]

For fifty years the people who built compressors were craftsmen. Someone sat down, thought hard about images, and *wrote down* a transform by hand — the discrete cosine transform of JPEG (Chapter 42), the wavelets of JPEG 2000 (Chapter 43), the integer transforms of H.264 (Chapter 52). Someone else hand-tuned a quantization table by squinting at test images. A third person hand-designed an entropy coder. Each box was a human decision, defended in a standards meeting, frozen into a specification, and shipped to billions of devices.

Then, around 2016, a small group of researchers asked a heretical question. *What if we never specify the transform at all?* What if, instead of a human writing down the DCT, we let a computer *discover* its own transform directly from a mountain of photographs — and what if the very thing it tried to minimize was the file size? Not a transform a person guessed would compress well, but a transform *grown*, knob by knob, to compress well, by a procedure that automatically tunes millions of knobs at once.

That procedure is *machine learning*, and the family of models that grew the best transforms is *neural networks*. By 2024 a learned image codec called JPEG AI had become the first international standard built this way, beating the best hand-built codec on Earth. To understand how a *learned* compressor works — which is the entire subject of Volume IV — you need just enough deep learning to follow the plot. That is exactly what this chapter delivers: neurons, gradient descent, autoencoders, and the menagerie of generative models, each introduced from scratch and each framed, from the first sentence, as *a way to learn the distribution of a source*. Because that, as Chapter 23 promised, is all compression ever was.

#recap[
In Chapter 11 we built a *gentle calculus*: the derivative as a slope, and the idea that following the slope downhill finds a minimum. In Chapter 12 we met *vectors and matrices* as bundles of numbers and the linear maps between them. Chapters 9 and 10 gave us *probability*, *random variables*, and *expectation*. Chapters 18–21 turned all of that into information theory: *entropy* is the true cost in bits (Chapter 19), and the *rate–distortion* curve is the unbeatable trade-off between file size and fidelity (Chapter 21). Most importantly, Chapter 23 proved this chapter's secret title — *compression is prediction is learning*: a model that predicts the next symbol well is, by the same arithmetic, a compressor that codes it cheaply. This chapter cashes that promise in. A neural network is just a flexible, trainable predictor; train it to predict your data, and you have grown yourself a compressor.
]

#objectives((
  [Read a *neuron* as a plain mathematical function: weighted sum, bias, squashing nonlinearity.],
  [Explain why stacking neurons into *layers* lets a network approximate almost any function.],
  [Follow *gradient descent* and *backpropagation* as "calculus rolling downhill," using only Chapter 11's slope idea.],
  [Describe an *autoencoder* and the *bottleneck*, and see why a narrow bottleneck *is* a lossy compressor.],
  [State the *rate–distortion loss* that a learned codec minimizes, and connect it to Chapter 21.],
  [Distinguish the four great generative families — *autoregressive*, *VAE*, *GAN*, *diffusion* — as four ways to learn a source distribution $p(x)$.],
  [Run a tiny neural autoencoder in NumPy and watch its bottleneck throw bits away.],
))

== From a hand-built transform to a learned one

Let us anchor everything in a picture we already own. Back in Chapter 42 the JPEG pipeline was a conveyor belt: an image went in, a *transform* (the DCT) rearranged its energy, a *quantizer* threw away the parts the eye won't miss (the only lossy step), and an *entropy coder* wrote the survivors to bits as cheaply as Shannon allows. Three boxes, three human inventions.

#fig([The classical codec (top) versus the learned codec (bottom). Same three jobs — transform, quantize, entropy-code — but in the learned version each box is a network whose knobs are tuned by gradient descent, all at once, against the file size itself.],
cetz.canvas({
  import cetz.draw: *
  let bx(x, y, w, t, c) = {
    rect((x,y),(x+w,y+0.9), fill: c, stroke: 0.6pt)
    content((x+w/2, y+0.45))[#text(size:7.5pt)[#t]]
  }
  content((-0.2, 2.85), anchor:"west")[#text(size:8pt, weight:"bold")[Classical (hand-built)]]
  bx(0, 2.0, 1.4, "DCT", rgb("#eef4fb"))
  bx(1.7, 2.0, 1.7, "quantize", rgb("#fbf2ee"))
  bx(3.7, 2.0, 2.0, "entropy code", rgb("#eef7ee"))
  line((1.4,2.45),(1.7,2.45), mark:(end:">"))
  line((3.4,2.45),(3.7,2.45), mark:(end:">"))
  content((-0.2, 1.25), anchor:"west")[#text(size:8pt, weight:"bold")[Learned (grown)]]
  bx(0, 0.4, 1.4, "encoder net", rgb("#e7eefc"))
  bx(1.7, 0.4, 1.7, "round", rgb("#f6e9e3"))
  bx(3.7, 0.4, 2.0, "learned model", rgb("#e3f1e3"))
  line((1.4,0.85),(1.7,0.85), mark:(end:">"))
  line((3.4,0.85),(3.7,0.85), mark:(end:">"))
  content((2.85,-0.35))[#text(size:7pt, fill:c-key)[all knobs tuned together by gradient descent]]
}))

In the learned version, the DCT box becomes a small network we will call the *encoder* $g_a$; the quantizer stays (rounding is still the lossy step); the entropy coder is driven by a *learned probability model*. The radical part is the word *learned*. Nobody writes down $g_a$. It starts as random numbers and is *shaped* by showing the system millions of images and nudging every knob, slightly, in whatever direction makes the output file a little smaller and the reconstruction a little better. Do that a few hundred million times and the random numbers settle into a transform that — astonishingly — beats the DCT a human spent a career perfecting.

To believe that this is even *possible*, we need three ingredients: (1) a *neuron*, the atom that does the nudging; (2) *gradient descent*, the nudging procedure; and (3) the *autoencoder*, the particular wiring that turns nudging into compression. We build them in order, owing nothing to prior knowledge.

== The neuron: a weighted sum with a squash

Forget biology. A neuron, in the sense that matters here, is a tiny mathematical function. It takes several numbers in and produces one number out. Here is the whole thing.

Suppose the inputs are three numbers, $x_1, x_2, x_3$. The neuron keeps a private list of *weights*, one per input — call them $w_1, w_2, w_3$ — and one extra number $b$ called the *bias*. It computes a weighted sum, adds the bias, and passes the result through a *squashing function* $f$:

$ y = f(w_1 x_1 + w_2 x_2 + w_3 x_3 + b). $

That is the entire neuron. The weights say how much each input matters (a big positive weight means "this input pushes the output up," a negative weight "pushes it down," a near-zero weight "ignore this input"). The bias shifts the whole thing up or down. The squashing function $f$ — we meet three of them in a moment — is the one nonlinear flourish that gives a neuron its power.

#gomaths("The weighted sum as a dot product")[
We met the *dot product* in Chapter 12. Bundle the inputs into a vector $bold(x) = (x_1, x_2, x_3)$ and the weights into $bold(w) = (w_1, w_2, w_3)$. Then the weighted sum is exactly the dot product plus the bias:
$ w_1 x_1 + w_2 x_2 + w_3 x_3 + b = bold(w) dot bold(x) + b. $
Why care? Because a *whole layer* of neurons — say 100 of them, each with its own weight vector — is just a *matrix* $W$ (one row per neuron) times the input vector, plus a bias vector $bold(b)$. A layer's output is $f(W bold(x) + bold(b))$, with $f$ applied to each entry. This is why neural networks live or die by fast matrix multiplication, and why GPUs (built to multiply matrices) run them. Everything is the linear algebra of Chapter 12, sprinkled with one nonlinear function.
]

Why the squash? If we left $f$ out — if a neuron were just $bold(w) dot bold(x) + b$ — then stacking neurons would buy us nothing. A linear function of a linear function is still linear (Chapter 12): a thousand layers without a squash collapse into a single matrix, able to draw only straight lines and flat planes. Real data — the boundary between "cat" and "dog," the texture of grass, the statistics of a photo — is gloriously *curved*. The nonlinear squash is what lets stacked neurons bend. Three squashes you will meet everywhere:

- *Sigmoid*, $sigma(z) = 1 \/ (1 + e^(-z))$, gently squashes any number into the range $(0, 1)$ — an S-curve, near 0 for very negative inputs, near 1 for very positive ones. It was the classic choice and still appears wherever an output must look like a probability.
- *ReLU*, the "rectified linear unit," $"ReLU"(z) = max(0, z)$ — pass positive numbers straight through, clamp negatives to zero. Absurdly simple, and it powers most modern networks because it is fast and its slope never vanishes for positive inputs.
- *Tanh*, the hyperbolic tangent, an S-curve like sigmoid but ranging over $(-1, 1)$ and centered at zero.

#gomaths("Euler's number e and the exponential")[
The sigmoid uses $e approx 2.71828$, *Euler's number*, the natural base of exponential growth from Chapter 7. The function $e^z$ doubles-and-redoubles smoothly; $e^(-z)$ shrinks smoothly toward zero as $z$ grows. So in $sigma(z) = 1\/(1 + e^(-z))$: when $z$ is large and positive, $e^(-z) approx 0$, so $sigma approx 1\/1 = 1$; when $z$ is large and negative, $e^(-z)$ is huge, so $sigma approx 1\/"huge" approx 0$; when $z = 0$, $e^0 = 1$ and $sigma = 1\/2$. A smooth switch from 0 to 1, hinged at the origin. The one fact to carry forward: $e^z$ is the function that is *its own slope* (its derivative equals itself), which is exactly why calculus loves it and why it makes the downhill-rolling of the next section easy.
]

#fig([Three squashing functions. Sigmoid and tanh are smooth S-curves; ReLU is a hinge. The squash is the single nonlinear ingredient that lets stacked neurons approximate curved functions.],
cetz.canvas({
  import cetz.draw: *
  line((-2.4,0),(2.4,0), mark:(end:">"))
  line((0,-1.3),(0,1.5), mark:(end:">"))
  content((2.5,-0.25))[#text(size:7pt)[$z$]]
  let sig(z) = 1.0/(1.0 + calc.exp(-2.0*z))
  line(..range(-24,25).map(i => {let z=i/10; (z, sig(z))}), stroke: 1pt + c-accent)
  content((1.5,1.15))[#text(size:7pt, fill:c-accent)[sigmoid]]
  line(..range(-24,25).map(i => {let z=i/10; (z, calc.tanh(1.6*z))}), stroke: 1pt + c-key)
  content((1.5,-1.0))[#text(size:7pt, fill:c-key)[tanh]]
  line((-2.2,0),(0,0),(1.0,1.0), stroke: 1pt + c-warn)
  content((-1.4,1.2))[#text(size:7pt, fill:c-warn)[ReLU]]
}))

#keyidea[
A neuron is *weighted sum → add bias → squash*. A layer is a *matrix multiply → add bias vector → squash, applied elementwise*. A network is *layers stacked one after another*. There is no other machinery. The intelligence is entirely in the *values* of the weights — and those values are not designed, they are *learned*.
]

=== Why stacking helps: the universal approximation theorem

Here is the result that justifies the whole enterprise. Imagine the true relationship you want to capture — say, the function mapping a raw image to its most compressible representation — is some impossibly complicated curve in high-dimensional space. Can a stack of these simple neurons reproduce it?

#theorem("Universal Approximation, informal")[
A network with a single hidden layer of squashing neurons can approximate *any* continuous function on a bounded region to *any* desired accuracy, provided the layer is wide enough.
]

This was proved independently by George Cybenko (December 1989) for sigmoid neurons and by Ken-Ichi Funahashi (May 1989), and it is the theoretical license for everything that follows: there is no curve, no transform, no decision boundary so baroque that a big enough network cannot mimic it. We will not prove it in full — it leans on real analysis beyond our ninth-grade contract — but the intuition is graspable and worth a sketch.

#proof[(Intuition, in one dimension.) Take a single sigmoid $sigma(w(x - c))$. With a large weight $w$ it becomes a sharp *step* that switches from 0 to 1 right at $x = c$. Subtract two such steps placed close together and you get a thin *bump* — a spike of height 1 over a narrow interval. Now you hold a paintbrush: by adding many bumps of different heights and positions (each bump is one pair of hidden neurons, scaled by an output weight), you can paint any continuous curve as a row of thin rectangles — exactly as Chapter 11 approximated the area under a curve by thin rectangles. More neurons, thinner bumps, better fit. The same argument generalizes to many dimensions. $square$]

#aside[The theorem is an *existence* result: it promises a good network *exists*, not that gradient descent will *find* it, nor that it will be small. In practice *depth* (many layers) is dramatically more parameter-efficient than the one fat layer the theorem uses — deep networks reuse features, building edges into textures into objects. The 2012–2020 deep-learning revolution was largely the discovery of how to actually *train* deep stacks, not a new theorem about what they could represent.]

#checkpoint[Why can't we drop the squashing function $f$ and just stack weighted sums?][Because a composition of linear functions is linear: $W_2(W_1 bold(x)) = (W_2 W_1) bold(x)$ is one matrix. Without a nonlinearity the deepest network collapses to a single linear map, able to represent only straight lines and flat planes — useless for the curved structure of real data.]

== Learning by rolling downhill: gradient descent

We have a network full of knobs (the weights and biases) and a promise that *some* setting of those knobs does the job. How do we *find* that setting among the millions of numbers? We do not search blindly. We roll downhill.

Picture the network's total error — how badly it does on the training data — as a *landscape*. Every possible setting of the weights is a point on the ground; the *height* at that point is the error. A perfect network sits at the bottom of a valley. We start somewhere random (high up, error large) and want to reach a valley floor. The trick comes straight from Chapter 11: at any point, the *slope* tells you which way is downhill. Take a small step in the steepest downhill direction. Repeat. This is *gradient descent*, the engine of all learning.

#gomaths("The gradient — a slope in many directions")[
In Chapter 11 the *derivative* of a one-input function was its slope: $(d L)\/(d w)$ tells you how much the error $L$ changes if you nudge the single knob $w$. With millions of knobs $w_1, dots, w_n$, each has its *own* slope — the *partial derivative* $(partial L)\/(partial w_i)$, meaning "the slope in the $w_i$ direction, holding all other knobs fixed." Stack these slopes into a vector:
$ nabla L = ((partial L)/(partial w_1), (partial L)/(partial w_2), dots, (partial L)/(partial w_n)). $
This vector is the *gradient* (the upside-down triangle $nabla$ is read "nabla" or "del"). Its single magical property: it points in the direction of *steepest increase* of $L$. So $-nabla L$ points *steepest downhill*. To shrink the error, step a little in the direction $-nabla L$:
$ w_i ← w_i - eta dot (partial L)/(partial w_i)  "for every knob" i. $
The small number $eta$ (Greek "eta") is the *learning rate*, the size of each step. Too big and you leap over the valley and bounce; too small and you crawl. That single update rule, applied over and over, is the whole of training.
]

#fig([Gradient descent on an error landscape. From a random start (high error), each step follows the downhill slope $-nabla L$ scaled by the learning rate $eta$, settling toward a valley floor.],
cetz.canvas({
  import cetz.draw: *
  let L(w) = 0.55*calc.pow(w,2) + 0.15*calc.sin(3*w)
  line(..range(-22,23).map(i => {let w=i/10; (w, L(w))}), stroke: 1pt + c-rule)
  content((2.3,2.4))[#text(size:7pt)[error $L$]]
  let pts = (-1.9, -1.35, -0.92, -0.6, -0.35, -0.18)
  for i in range(pts.len()) {
    let w = pts.at(i)
    circle((w, L(w)), radius: 0.06, fill: c-accent, stroke: none)
  }
  for i in range(pts.len()-1) {
    let w0 = pts.at(i); let w1 = pts.at(i+1)
    line((w0, L(w0)), (w1, L(w1)), stroke: 0.7pt + c-accent, mark:(end:">"))
  }
  content((-1.5, L(-1.9)+0.3))[#text(size:7pt, fill:c-accent)[start]]
  content((0.0, -0.5))[#text(size:7pt, fill:c-key)[minimum]]
  content((0,-1.05))[#text(size:7pt)[knob $w$]]
}))

The one thing left to explain is *how we compute the gradient* of a deep stack. With millions of knobs buried under many layers, computing each partial derivative from scratch would be hopeless. The rescue is an old idea with a famous 1986 paper: *backpropagation*.

=== Backpropagation: the chain rule, run backward

The error depends on the final layer's output, which depends on the layer before, which depends on the layer before that, all the way back to the first weights. To find how a deep-down weight affects the error, you must trace the influence *through* every layer in between. The tool for "the slope of a function of a function" is the *chain rule* from Chapter 11.

#gomaths("The chain rule")[
If $z$ depends on $y$ and $y$ depends on $x$, then a nudge in $x$ ripples through $y$ to $z$, and the slopes *multiply*:
$ (d z)/(d x) = (d z)/(d y) dot (d y)/(d x). $
Concretely, if $y = 3x$ (so $(d y)\/(d x) = 3$) and $z = y^2$ (so $(d z)\/(d y) = 2y$), then $(d z)\/(d x) = 2y dot 3 = 6y = 18 x$. Influence is *transmitted* by multiplying the local slopes along the path. A neural network is a long chain $x → "layer"_1 → "layer"_2 → dots → "error"$, so the slope of the error with respect to any early weight is a product of local slopes, one per layer it must pass through.
]

*Backpropagation* (Rumelhart, Hinton, and Williams popularized it in a celebrated 1986 *Nature* paper, though the core idea dates to Linnainmaa in 1970 and Werbos in 1974) is simply the chain rule applied *cleverly*: instead of recomputing the long product for every weight, you compute the error's slope at the output and *propagate it backward*, layer by layer, reusing the partial products. Each layer receives "how much the error blames my output" from the layer above, multiplies by its own local slope to get "how much the error blames my inputs," and passes that down. One forward pass to compute the output, one backward pass to compute every gradient. The cost is roughly *two* network evaluations no matter how many weights — which is why training billion-parameter models is even thinkable.

#fig([One training step. Forward pass (blue): data flows up through the layers to produce a prediction and an error. Backward pass (orange): the error's blame flows back down, the chain rule handing each layer its gradient, and every weight steps downhill.],
cetz.canvas({
  import cetz.draw: *
  let lay(y, t) = {
    rect((0,y),(2.2,y+0.7), fill: c-soft, stroke: 0.6pt)
    content((1.1,y+0.35))[#text(size:7.5pt)[#t]]
  }
  lay(0, [input $bold(x)$])
  lay(1.0, [layer 1])
  lay(2.0, [layer 2])
  lay(3.0, [error $L$])
  // forward
  line((2.2,0.35),(2.9,0.35),(2.9,1.35),(2.2,1.35), stroke:1pt+c-accent, mark:(end:">"))
  line((2.2,1.35),(2.9,1.35),(2.9,2.35),(2.2,2.35), stroke:1pt+c-accent, mark:(end:">"))
  line((2.2,2.35),(2.9,2.35),(2.9,3.35),(2.2,3.35), stroke:1pt+c-accent, mark:(end:">"))
  content((3.5,1.85))[#text(size:7pt, fill:c-accent)[forward]]
  // backward
  line((0,3.35),(-0.7,3.35),(-0.7,2.35),(0,2.35), stroke:1pt+c-warn, mark:(end:">"))
  line((0,2.35),(-0.7,2.35),(-0.7,1.35),(0,1.35), stroke:1pt+c-warn, mark:(end:">"))
  line((0,1.35),(-0.7,1.35),(-0.7,0.35),(0,0.35), stroke:1pt+c-warn, mark:(end:">"))
  content((-1.55,1.85))[#text(size:7pt, fill:c-warn)[backward (gradients)]]
}))

#history[The 1986 paper, "Learning representations by back-propagating errors," is one of the most cited in all of science, yet backpropagation was independently discovered several times — Seppo Linnainmaa described reverse-mode automatic differentiation in his 1970 master's thesis, and Paul Werbos proposed using it to train networks in his 1974 PhD thesis. Geoffrey Hinton, a co-author of the 1986 paper, would share the 2024 Nobel Prize in Physics for foundational work on neural networks — a sign of how thoroughly the once-fringe idea conquered the mainstream.]

#pitfall[The error landscape of a real network is *not* a single clean bowl — it is a vast, lumpy terrain with many valleys (*local minima*), flat plains (*saddle points*), and ravines. Gradient descent can get stuck or crawl. The practical fixes you will hear named — *stochastic* gradient descent (estimate the slope from a small random *batch* of examples, not the whole dataset, so each step is cheap and noisy enough to escape shallow traps), *momentum*, and the *Adam* optimizer — are all refinements of the same downhill idea. The headline never changes: *compute the gradient, step downhill, repeat.*]

#checkpoint[Backpropagation computes the gradient in time proportional to roughly how many forward passes, regardless of the number of weights?][About two — one forward pass to compute the output and error, one backward pass to compute the gradient for *every* weight at once. That constant-factor cost (independent of parameter count) is what makes training enormous models feasible.]

#algo(
  name: "Gradient descent (with backpropagation)",
  year: "1847 / 1986",
  authors: "Cauchy (descent); Rumelhart, Hinton, Williams (backprop, popularized)",
  aim: "Find weights that minimize a loss function, by repeatedly stepping in the steepest downhill direction.",
  complexity: "Per step: two network evaluations (one forward, one backward), independent of weight count.",
  strengths: "Scales to billions of parameters; needs only first derivatives; trivially parallel on GPUs.",
  weaknesses: "Finds *a* minimum, not the global one; sensitive to learning rate; slow on ill-conditioned landscapes.",
  superseded: "Refined, not replaced, by SGD, momentum, RMSProp, and Adam — all the same downhill idea.",
)[
  Initialize the weights randomly. Repeat for many steps: (1) *forward* — push a batch of training examples through the network to get predictions and a loss $L$; (2) *backward* — run backpropagation to get $nabla L$, the slope with respect to every weight; (3) *update* — for each weight, $w ← w - eta dot (partial L)\/(partial w)$. Stop when $L$ stops dropping. The discovered weights *are* the trained model.
]

== The autoencoder: a bottleneck that *is* a compressor

Now we wire neurons into the shape that does compression. An *autoencoder* is two networks glued back to back, trained to copy their input to their output through a deliberately *narrow* middle.

The first network, the *encoder* $g_a$, reads the input $bold(x)$ (say an image, flattened into a long vector of pixel values) and squeezes it down through shrinking layers to a small vector $bold(y) = g_a(bold(x))$, the *latent code* or *bottleneck*. The second network, the *decoder* $g_s$, reads $bold(y)$ and expands it back up to a reconstruction $hat(bold(x)) = g_s(bold(y))$ the same size as the input. The training goal is simply: *make $hat(bold(x))$ look like $bold(x)$*. The loss is the *reconstruction error*, typically the mean squared difference between the original and the copy,
$ D = 1/N sum_(i=1)^N (x_i - hat(x)_i)^2, $
averaged over the pixels. Gradient descent tunes both networks together to minimize it.

#gomaths("Mean squared error")[
*Mean squared error* (MSE) measures how far two lists of numbers are apart. For each position $i$, take the difference $x_i - hat(x)_i$, *square* it (so positive and negative errors both count, and big errors count disproportionately), then *average* over all $N$ positions. MSE $= 0$ means a perfect copy; larger MSE means a worse one. In Chapter 21 we called the average reconstruction error the *distortion* $D$ — MSE is the most common choice of $D$, which is exactly why we reuse the letter here. (We met squaring and averaging in Chapter 10's *variance*, which is itself an MSE around the mean.)
]

Here is the crucial twist. If the bottleneck $bold(y)$ were *as big as* the input, the autoencoder could cheat: the encoder copies the input verbatim, the decoder copies it back, reconstruction perfect, nothing learned. The magic is in the word *narrow*. We force $bold(y)$ to be *smaller* than $bold(x)$ — fewer numbers in the middle than at the ends. Now the network *cannot* pass everything through; it must decide what to keep and what to discard. To minimize reconstruction error under that constraint, it is forced to learn the *structure* of the data — the regularities that let a few numbers stand in for many. That is the definition of a *transform that decorrelates*: it is doing, automatically, the job the DCT did by hand.

#definition("Autoencoder")[A pair of networks — an encoder $g_a: bold(x) ↦ bold(y)$ and a decoder $g_s: bold(y) ↦ hat(bold(x))$ — trained jointly to minimize the reconstruction error between $bold(x)$ and $hat(bold(x))$, with the latent $bold(y)$ constrained to be a *bottleneck* (lower-dimensional, or otherwise limited). The bottleneck forces the network to learn a compact code for the data.]

#fig([An autoencoder. The encoder funnels the input down to a small latent bottleneck $bold(y)$; the decoder funnels it back up to a reconstruction $hat(bold(x))$. The narrow middle forces the network to keep only what matters — which is exactly compression.],
cetz.canvas({
  import cetz.draw: *
  // pure helper: just compute the y-coordinates for a column of n nodes
  let ys-of(n, h) = {
    let ys = ()
    for i in range(n) { ys.push(h/2 - i*(h/(calc.max(n - 1, 1)))) }
    ys
  }
  let cols = ((0, 5, 2.4), (1.3, 3, 1.5), (2.6, 2, 0.7), (3.9, 3, 1.5), (5.2, 5, 2.4))
  let coords = cols.map(c => (c.at(0), ys-of(c.at(1), c.at(2))))
  // draw the fully-connected edges between adjacent columns
  for k in range(coords.len() - 1) {
    let (xa, ya) = coords.at(k)
    let (xb, yb) = coords.at(k + 1)
    for a in ya { for b in yb { line((xa, a), (xb, b), stroke: 0.25pt + c-rule) } }
  }
  // draw the nodes on top
  for (x, ys) in coords {
    for y in ys { circle((x, y), radius: 0.11, fill: c-accent, stroke: none) }
  }
  content((0,-1.65))[#text(size:7pt)[$bold(x)$ in]]
  content((2.6,-1.0))[#text(size:7pt, fill:c-key, weight:"bold")[bottleneck $bold(y)$]]
  content((5.2,-1.65))[#text(size:7pt)[$hat(bold(x))$ out]]
  content((0.65,1.55))[#text(size:7pt, fill:c-accent)[encoder $g_a$]]
  content((4.55,1.55))[#text(size:7pt, fill:c-accent)[decoder $g_s$]]
}))

#keyidea[
A narrow autoencoder *is* a lossy compressor. To store an image you run the encoder and keep only the small latent $bold(y)$; to view it you run the decoder. The compression ratio is the size of $bold(x)$ over the size of $bold(y)$ — fewer numbers in, fewer bits stored. The reconstruction is imperfect (lossy) precisely because the bottleneck threw information away. Everything left to do — quantizing $bold(y)$, entropy-coding it, and putting the *bitrate* into the loss — turns this sketch into a real codec.
]

=== Three problems on the road to a real codec

The bare autoencoder above is a transform with a bottleneck. To become an actual file format it must solve three problems, each of which became a small research milestone.

*Problem 1 — the latent is still real numbers.* The bottleneck $bold(y)$ is a vector of floating-point numbers, and you cannot write an infinitely precise real number to a finite file (Chapter 13). You must *quantize* it — round each number to a finite grid — just as JPEG rounded DCT coefficients (Chapter 42). Rounding is the only lossy step beyond the bottleneck.

*Problem 2 — rounding has no slope.* Here is the headache that nearly sank the field. Gradient descent needs slopes (Chapter 11). But the rounding function $hat(y) = round(y)$ is a *staircase*: flat between integers (slope 0) with vertical jumps at the half-integers (slope undefined). A flat function has zero gradient *everywhere it is defined*, so backpropagation sees no signal — nudging $y$ a little does not change $round(y)$ at all, so the network is told "rounding doesn't matter," which is catastrophically wrong. We cannot train through a staircase.

The fix, due to Ballé and colleagues in 2016–17 and now universal, is the *quantization-as-noise* trick. During *training*, replace the hard rounding by adding a little *uniform random noise*: instead of $round(y)$, use $y + u$ where $u$ is a random number drawn evenly from $(-1/2, +1/2)$. This soft surrogate has two beautiful properties: it is smooth (so gradients flow), and its random spread of $plus.minus 1/2$ *mimics* the error that real rounding introduces. The network trains against a faithful, differentiable stand-in for quantization. At *test* time you switch back to true rounding. We will meet this trick again, in full, in Chapter 57.

*Problem 3 — we must count the bits.* A bottleneck that is *small* is good, but what we truly pay for is *bits*, and bits depend on the *probabilities* of the latent values (Chapter 19: a symbol of probability $p$ costs $-log_2 p$ bits). So the codec carries a *learned probability model* $p(hat(bold(y)))$ for its own latents, and the bit cost — the *rate* — is the expected codelength under that model. This is the deep link back to Chapter 23: *the model that predicts the latents well is the model that codes them cheaply.* And, crucially, the rate can be written as a differentiable formula, so we can put it *into the loss* and let gradient descent shrink the file directly.

== The rate–distortion loss: compression as one optimization

Now assemble the pieces into the single objective that defines learned compression. We want a *small file* (low rate $R$) *and* a *faithful reconstruction* (low distortion $D$). These pull in opposite directions — exactly the tension Chapter 21 made precise as the *rate–distortion trade-off*. We balance them with a knob:

$ cal(L) = R + lambda D = underbrace(-log_2 p(hat(bold(y))), "bits to store the latent") + lambda underbrace(D(bold(x), hat(bold(x))), "reconstruction error"). $

Read it slowly. The first term $R$ is the codelength of the quantized latent under the learned model — the *bitrate*. The second term $D$ is the reconstruction distortion, usually MSE. The number $lambda$ (Greek "lambda") is a *Lagrange multiplier*: it sets the exchange rate between bits and quality. Crank $lambda$ up and the optimizer cares mostly about quality, spending bits freely (a big, sharp file); crank it down and it cares mostly about size, tolerating blur (a tiny file). Sweep $lambda$ and you trace out the whole rate–distortion curve of Chapter 21 — but now the points on that curve are achieved by a *trained network*, not a hand-built codec.

#gomaths("Lagrange multipliers, the one-line version")[
You want to make $D$ as small as possible, but you also care about keeping $R$ small — two goals at once. The *Lagrange* trick turns "minimize $D$ subject to a budget on $R$" into "minimize the single combined quantity $R + lambda D$" for some positive weight $lambda$. Each choice of $lambda$ corresponds to one budget; minimizing the combined quantity for that $lambda$ lands you at the best $D$ achievable for the matching $R$ — a point on the rate–distortion frontier. We met this balancing-of-two-costs idea in Chapter 21; here it is the entire training objective.
]

#mathrecall[The *KL divergence* (relative entropy) of Chapter 20, written $D_("KL")(q parallel p)$, measures the extra bits you pay for coding data that truly follows $q$ with a code built for a different distribution $p$. It is never negative, and zero exactly when $q = p$. Keep that one fact handy — the rate term below *is* a KL divergence in disguise.]

#theorem("RD loss is the variational-autoencoder objective")[
Minimizing the rate–distortion loss $R + lambda D$ with the quantization-as-noise surrogate is mathematically *identical* to training a *variational autoencoder* (VAE), in which the rate term plays the role of the *KL divergence* between the (noisy) latent and a prior, and the distortion term plays the role of the reconstruction likelihood.
]

#proof[(Sketch.) A VAE (next section) maximizes a quantity called the *evidence lower bound*, which has exactly two terms: a *reconstruction* term rewarding $hat(bold(x)) approx bold(x)$, and a *KL-divergence* term penalizing the latent for straying from a fixed prior $p(bold(y))$. When the encoder's latent distribution is "the true value plus uniform noise of width 1," the reconstruction term becomes (up to a constant) the MSE distortion $D$, and the KL term becomes (up to a constant) the expected codelength $-log_2 p(hat(bold(y)))$, i.e. the rate $R$. So "evidence lower bound" $=$ "$-(R + lambda D)$" up to scaling. Maximizing the one is minimizing the other. Compression *is* variational inference; the bottleneck-with-a-price-tag and the VAE are the same animal wearing two hats. $square$]

This equivalence, pointed out in the very papers that launched learned compression, is one of the most beautiful bridges in the field: the information-theoretic quantity "bits" and the statistical quantity "KL divergence from the prior" are the same number (we proved their kinship in Chapter 20's relative-entropy / KL-divergence material). It means every advance in generative modeling is, potentially, an advance in compression — which is why the rest of this chapter tours the generative zoo.

#scoreboard(
  caption: "where learned codecs sit (still-image, BD-rate vs. the best classical codec; lower file at equal quality is better)",
  [JPEG (1992, DCT)], [baseline], [—], [hand-built; Chapter 42],
  [BPG / HEVC-intra (2014)], [≈ −60%], [much smaller], [hand-built; Chapter 53],
  [Minnen 2018 (learned, context model)], [beats BPG], [−15.8% vs. prior learned], [first learned codec to beat BPG on PSNR + MS-SSIM],
  [VVC-intra (2020)], [≈ −25% vs. HEVC], [smaller still], [hand-built; Chapter 53],
  [JPEG AI (ISO/IEC 6048-1:2025)], [up to −28.5% vs. VVC], [smallest], [first learned *international standard*; Chapter 57],
)

The scoreboard tells the headline of Volume IV in one glance: the learned curve, born clumsy in 2016, crossed the best hand-built codec by 2018 and by 2025 had become a published international standard beating VVC. Chapter 57 builds the exact architecture (the Ballé hyperprior line) that achieved it.

== Four ways to learn a source distribution

Step back. Chapter 23 taught the deepest idea in this book: *to compress a source optimally is to know its probability distribution $p(x)$*. If you know exactly how likely every possible message is, an arithmetic coder (Chapter 26) spends $-log_2 p(x)$ bits on message $x$ and you have hit the Shannon floor. Every compressor is, secretly, a model of $p(x)$ — Huffman, PPM, LZ, all of them. The deep-learning revolution gave us *powerful, trainable* models of $p(x)$ for data far too complex to model by hand: images, audio, language. These are the *generative models*, so named because a model of $p(x)$ can also *generate* new samples by drawing from it.

There are four great families, and the single most useful way to keep them straight is to ask: *how does each one represent $p(x)$, and how does each turn into a compressor?* We tour them in the order they were invented.

=== Family 1 — Autoregressive models: predict the next piece

The most direct route reuses an idea we have leaned on since Chapter 23. Break the data into an ordered sequence of pieces — pixels left-to-right, top-to-bottom, or the tokens of a sentence — and model the probability of each piece *given all the pieces before it*. The *chain rule of probability* (Chapter 9) then assembles the whole:

$ p(x_1, x_2, dots, x_n) = p(x_1) dot p(x_2 | x_1) dot p(x_3 | x_1, x_2) dots p(x_n | x_1, dots, x_(n-1)). $

A neural network supplies each conditional $p(x_k | "everything before")$: feed it the context, it outputs a probability for the next piece. Train it to predict well (minimize the surprise of the real next piece — which is exactly the cross-entropy of Chapter 23), and you have a model that, paired with an arithmetic coder, compresses to within a whisker of its own cross-entropy. This is the *purest* embodiment of "compression = prediction," and it is precisely how PNG predicts pixels, how PPM predicts characters, and — at gigantic scale — how a large language model predicts words. Chapter 62 will build an LLM-driven compressor on exactly this principle.

#algo(
  name: "Autoregressive model",
  year: "1980s–; PixelRNN/PixelCNN 2016; GPT-style 2018–",
  authors: "van den Oord et al. (PixelRNN/CNN); many for language",
  aim: "Model $p(x)$ as a product of next-piece conditionals $p(x_k | x_(<k))$, each predicted by a network.",
  complexity: "Decoding is *serial*: piece $k$ needs piece $k-1$; $n$ pieces means $n$ network passes.",
  strengths: "Exact likelihood (so exact, optimal coding); conceptually simplest; state-of-the-art prediction quality.",
  weaknesses: "Serial decode is slow — the field's central wound for image/video codecs.",
  superseded: "Complemented (not replaced) by VAEs, GANs, diffusion; still the backbone of LLM compression (Chapter 62).",
)[
  In learned image compression the autoregressive idea reappears as the *context model*: each latent element is predicted from its already-decoded neighbors, squeezing out the last redundancy. Minnen, Ballé, and Toderici (NeurIPS 2018) combined this with a hyperprior to become the first learned codec to beat BPG — at the cost of slow serial decoding (Chapter 57).
]

=== Family 2 — Variational autoencoders (VAEs): a probabilistic bottleneck

We have already met the VAE in disguise — it is the autoencoder whose loss is the rate–distortion loss. The *variational* twist makes the bottleneck *probabilistic*: instead of the encoder emitting one fixed latent vector, it emits a small *cloud* (a mean and a spread) of plausible latents, and a *prior* says what latents are expected in general. Training maximizes the *evidence lower bound* — reconstruct well, while keeping the latent cloud close to the prior. As we proved above, that is term-for-term the rate–distortion loss, with the "close to the prior" penalty *being* the bitrate.

#algo(
  name: "Variational Autoencoder (VAE)",
  year: "2013",
  authors: "Diederik Kingma, Max Welling",
  aim: "Learn a probabilistic latent code: encode $x$ to a distribution over latents, decode samples back, regularized toward a prior.",
  complexity: "One forward + one backward pass; fast, parallel encode and decode.",
  strengths: "Principled probabilistic objective; the exact framework of learned compression; fast non-serial decoding.",
  weaknesses: "MSE-trained VAEs produce *blurry* samples at low rates (the curse of averaging).",
  superseded: "Extended by hyperpriors (Ch 57), discretized as VQ-VAE, and combined with GANs/diffusion for sharpness.",
)[
  The VAE is the mathematical home of learned compression: Ballé's hyperprior codec (Chapter 57) is a two-level VAE, and the discrete *VQ-VAE* (van den Oord, 2017) — which snaps latents to entries of a learned codebook — became the tokenizer underneath many image and audio codecs.
]

The VAE's flaw is instructive and sets up the next two families. Trained on MSE, at low bitrate it produces *blurry* reconstructions. Why? Because when many fine details are equally plausible (the exact arrangement of blades of grass), the choice that minimizes *average squared error* is to draw their *average* — a smear. MSE rewards safe blur over risky detail. The eye, however, *hates* blur. To make low-rate reconstructions look *real* rather than *average*, we need a different yardstick than MSE — one that rewards matching the *distribution* of natural images, not the pixel-wise average. That yardstick was named *perception*, and Chapter 58 is devoted to it. The next two families are how we optimize for it.

=== Family 3 — Generative adversarial networks (GANs): a forger and a detective

A GAN learns $p(x)$ through a duel. Two networks train against each other. The *generator* tries to produce fake samples (here: reconstructions) that look like real data. The *discriminator* (a detective) is shown a mix of real images and the generator's fakes and trained to tell them apart. The generator is rewarded for *fooling* the detective. As they spar, the forger is driven to produce images statistically indistinguishable from real ones — which means sharp, plausible texture, exactly what MSE refused to draw.

#gomaths("A minimax game")[
The two networks optimize *opposite* goals on the same quantity, a *minimax* game — one side pushing a number *up* while the other pushes it *down*. The discriminator $D$ tries to *maximize* its accuracy at spotting fakes; the generator $G$ tries to *minimize* that same accuracy. Written compactly, they jointly seek $min_G max_D V(G, D)$ where $V$ measures the detective's success. At the ideal balance point the fakes are so good the detective can only guess — its accuracy stuck at 50% — and the generator's output distribution has matched the real data distribution $p(x)$. Training is a tug-of-war that, when it works, ends in a perfect draw.
]

In a *GAN codec*, the decoder is the generator: it must reconstruct a believable image from the transmitted code, and an adversarial detective pushes it toward realism. The landmark is *HiFiC* (Mentzer et al., NeurIPS 2020), which at one bitrate was preferred by human viewers over MSE codecs spending *twice* the bits. The honest catch — explored in Chapter 58 — is that these reconstructions are *generated*, not faithful: the network *hallucinates* texture that is statistically right but may not be the texture that was actually there. Plausible is not the same as true.

#algo(
  name: "Generative Adversarial Network (GAN)",
  year: "2014",
  authors: "Ian Goodfellow et al.",
  aim: "Learn $p(x)$ implicitly by training a generator to fool a discriminator that learns to spot fakes.",
  complexity: "Fast single-pass generation; *training* is notoriously unstable.",
  strengths: "Razor-sharp, realistic samples; excellent for low-bitrate perceptual compression (HiFiC).",
  weaknesses: "Unstable training (mode collapse); no exact likelihood; reconstructions can hallucinate.",
  superseded: "Largely overtaken by diffusion models for perceptual quality after 2022.",
)[
  GANs do not give a probability $p(x)$ you can read off (the model is *implicit*), so a GAN cannot directly drive an arithmetic coder. In a codec it is bolted onto an autoencoder: the autoencoder transmits the code and counts the bits, while the GAN loss reshapes the *decoder* to render realistic detail. See HiFiC, Chapter 58.
]

=== Family 4 — Diffusion models: sculpting an image out of noise

The newest and now-dominant family generates by *reversing a destruction process*. Take a clean image and add a tiny bit of random noise; repeat hundreds of times until nothing is left but pure static. That *forward* process is trivial. The magic is training a network to run it *backward* — to take noisy static and, step by step, *denoise* it back into a clean image, each step removing a little noise and adding a little structure. Once trained, you start from fresh random static and let the network sculpt an image out of it. Because each denoising step is a small, learnable nudge, diffusion models are remarkably stable to train (unlike GANs) and produce the sharpest, most realistic samples yet.

#algo(
  name: "Diffusion model (DDPM)",
  year: "2015 / 2020",
  authors: "Sohl-Dickstein et al. (2015); Ho, Jain, Abbeel (DDPM, 2020)",
  aim: "Learn $p(x)$ by training a network to reverse a gradual noising process, denoising static into data.",
  complexity: "Generation is *multi-step* (tens to thousands of passes) — historically very slow.",
  strengths: "State-of-the-art realism; stable training; powers ultra-low-bitrate generative codecs.",
  weaknesses: "Slow multi-step sampling (being fixed by one-step distillation); like GANs, can hallucinate.",
  superseded: "Current frontier; 2025 one-step distilled variants make it real-time.",
)[
  In a *diffusion codec* the decoder is a diffusion model *conditioned* on the transmitted code: it denoises static toward the image the code describes. By 2025 codecs such as *StableCodec* (ICCV 2025) and *OneDC* (NeurIPS 2025) piggybacked on huge pre-trained text-to-image diffusion models to reach *ultra-low* bitrates below $0.05$ bits per pixel — transmitting a semantic sketch and letting the generative prior fill in the rest. Their old weakness, glacial multi-step denoising, is being cured by *one-step distillation*: OneDC reports roughly $20 times$ faster decoding than multi-step diffusion codecs at comparable quality. Chapter 58 dissects them.
]

#misconception[A generative codec "remembers" the original image perfectly and just stores it cleverly.][A low-bitrate generative codec *reconstructs a plausible image*, not the true one. It transmits a compact description and lets a generative prior *invent* detail that is statistically consistent but possibly never present in the original — a real hazard for medical, legal, or forensic images, where an invented-but-plausible detail is worse than honest blur. We weigh this trade-off carefully in Chapter 58.]

#fig([The four generative families as four ways to represent the source distribution $p(x)$. All four can be turned into compressors, each with a different speed/quality/faithfulness profile.],
cetz.canvas({
  import cetz.draw: *
  let card(x, y, t, s) = {
    rect((x,y),(x+3.0,y+1.0), fill:c-soft, stroke:0.6pt+c-accent, radius:3pt)
    content((x+1.5,y+0.7))[#text(size:7.5pt, weight:"bold")[#t]]
    content((x+1.5,y+0.28))[#text(size:6.5pt, fill:c-ink.lighten(15%))[#s]]
  }
  card(0, 1.3, "Autoregressive", "exact $p$, serial, slow")
  card(3.4, 1.3, "VAE", "probabilistic bottleneck")
  card(0, 0.0, "GAN", "sharp, implicit $p$")
  card(3.4, 0.0, "Diffusion", "realistic, multi-step")
  content((3.2,2.55))[#text(size:8pt, weight:"bold", fill:c-key)[models of $p(x)$ → compressors]]
}))

== A neuron, a layer, and a network in Python

Enough abstraction — let us build the machinery in code, with nothing but NumPy, so the boxes above stop being metaphors. We use NumPy because neural networks *are* matrix arithmetic, and NumPy makes matrices a one-liner.

#gopython("NumPy arrays and matrix multiply")[
NumPy is Python's array library. An *array* is a grid of numbers — a vector, a matrix, or higher. You create one from a list, and arithmetic works *elementwise* (the whole grid at once), which is both fast and exactly how a layer of neurons works.
```python
import numpy as np

x = np.array([1.0, 2.0, 3.0])          # a length-3 vector
W = np.array([[0.5, 0.0, -1.0],        # a 2x3 matrix: 2 neurons,
              [1.0, 1.0,  0.0]])        #               3 inputs each
b = np.array([0.1, -0.2])              # one bias per neuron
print(W @ x + b)        # @ is matrix multiply -> [-2.4, 2.8]
```
The `@` operator is matrix multiplication: row $i$ of `W` is dotted with `x`, giving neuron $i$'s weighted sum. Add the bias vector `b` and you have the pre-squash output of a whole layer in one line — the `f(W x + b)` from the maths box, minus the squash.
]

#gopython("Defining functions with def, and type hints")[
We have used Python functions since Chapter 16. A quick refresh: `def name(arg: type) -> rettype:` declares a function; the `: type` and `-> rettype` are *type hints* (Chapter 15) — documentation the reader (and tools) can check, ignored at run time. NumPy arrays are typed `np.ndarray`.
```python
def relu(z: np.ndarray) -> np.ndarray:
    return np.maximum(0.0, z)     # elementwise max with 0
```
`np.maximum(0.0, z)` compares every entry of `z` against 0 and keeps the larger — the ReLU squash, applied to a whole array at once.
]

Here is a complete, runnable feed-forward network: a stack of *(matrix multiply, add bias, squash)* layers. It is the encoder or decoder of an autoencoder, in eight lines.

```python
import numpy as np

def sigmoid(z: np.ndarray) -> np.ndarray:
    return 1.0 / (1.0 + np.exp(-z))           # the S-curve squash

def forward(x: np.ndarray, layers: list[tuple[np.ndarray, np.ndarray]],
            squash) -> np.ndarray:
    """Run x through each (weight, bias) layer with a squash between."""
    a = x
    for (W, b) in layers:                      # one layer at a time
        a = squash(W @ a + b)                  # matrix-multiply, bias, squash
    return a

# a tiny 4 -> 2 -> 4 autoencoder, random weights (untrained)
rng = np.random.default_rng(0)
enc = [(rng.normal(size=(2, 4)), rng.normal(size=2))]   # 4 in -> 2 latent
dec = [(rng.normal(size=(4, 2)), rng.normal(size=4))]   # 2 latent -> 4 out

x = np.array([0.9, 0.1, 0.8, 0.2])
y = forward(x, enc, sigmoid)        # the 2-number bottleneck (latent)
xhat = forward(y, dec, sigmoid)     # the 4-number reconstruction
print("latent  :", y.round(3))
print("recon   :", xhat.round(3))
```

Run it and you get a 4-number input squeezed to a 2-number latent and expanded back to 4 numbers. With *random* weights the reconstruction is garbage — the network has not learned anything. The whole point of training is to find weights that make `xhat` resemble `x`. That requires gradient descent, which we now wire into the tinyzip project as the chapter's build step.

#project("Step 21 · A learned-transform sketch (`llmzip`-adjacent, NumPy)")[
TINYZIP's Phase D opens with a *concept-level* learned transform. We add a tiny module that *trains* a 2-pixel-wide autoencoder bottleneck on a stream of correlated pairs and shows it discovering, by gradient descent alone, the same "keep the average, drop the difference" structure a hand-built transform would impose — and watch the bottleneck *throw bits away*. This is a teaching sketch, not a production codec; the real Ballé architecture arrives in Chapter 57. We keep the names ready for `tinyzip/llmzip.py` (the neural module Chapter 62 completes).

```python
# tinyzip/learned.py  -- concept-level learned transform (Step 21)
import numpy as np

def sigmoid(z): return 1.0 / (1.0 + np.exp(-z))

def train_autoencoder(data: np.ndarray, latent: int = 1,
                      epochs: int = 4000, eta: float = 0.5,
                      seed: int = 0) -> dict[str, np.ndarray]:
    """Train a linear d->latent->d autoencoder by gradient descent.

    data: shape (N, d) rows are examples. Returns the learned weights.
    Linear (no squash) so the gradients are short and exact -- this is
    the simplest possible learned transform, a learned PCA.
    """
    rng = np.random.default_rng(seed)
    N, d = data.shape
    We = rng.normal(scale=0.5, size=(latent, d))   # encoder weights
    Wd = rng.normal(scale=0.5, size=(d, latent))   # decoder weights
    for _ in range(epochs):
        y = data @ We.T                 # (N, latent)  the bottleneck
        xhat = y @ Wd.T                 # (N, d)       reconstruction
        err = xhat - data               # (N, d)       what we got wrong
        # backprop the MSE through the two linear layers (chain rule):
        gWd = err.T @ y / N             # slope wrt decoder weights
        gWe = (err @ Wd).T @ data / N   # slope wrt encoder weights
        Wd -= eta * gWd                 # step downhill
        We -= eta * gWe
    return {"We": We, "Wd": Wd}

def encode(x: np.ndarray, w: dict[str, np.ndarray]) -> np.ndarray:
    return x @ w["We"].T                # x -> latent

def decode(y: np.ndarray, w: dict[str, np.ndarray]) -> np.ndarray:
    return y @ w["Wd"].T                # latent -> reconstruction

if __name__ == "__main__":            # tiny self-test
    rng = np.random.default_rng(1)
    # correlated pairs: each pixel pair is (a, a+small noise)
    a = rng.normal(size=(2000, 1))
    data = np.hstack([a, a + 0.05 * rng.normal(size=(2000, 1))])
    w = train_autoencoder(data, latent=1)
    y = encode(data, w)
    xhat = decode(y, w)
    mse = float(np.mean((xhat - data) ** 2))
    print(f"latent dim 1 (half the data), MSE = {mse:.5f}")
    # the learned encoder row ~ proportional to (1, 1): it kept the
    # *sum/average* of the pair and discarded the tiny *difference* --
    # exactly the decorrelating move a hand-built transform makes.
    print("encoder row:", (w["We"][0] / np.abs(w["We"][0]).max()).round(2))
```

Running it prints a small MSE (about $0.01$ — almost all of it the unrecoverable per-pixel noise) even though the single latent number stores *half* as many values as the input — because the two pixels were nearly identical, so one number (their shared value) reconstructs both almost perfectly. The printed encoder row comes out close to $(1, 1)$: gradient descent *discovered*, with no human hint, that the smart move is to keep the *average* of the correlated pair and throw the *difference* away. That is the entire idea of a decorrelating transform (Chapter 38's Karhunen–Loève transform, the ideal decorrelator, and its statistical cousin PCA), grown from random numbers by rolling downhill. Scale this from 2 pixels to whole images, swap the linear layers for deep nonlinear ones, add quantization and a learned entropy model, and you have the architecture of Chapter 57.
]

#pyrecall[`data @ We.T` multiplies the whole batch of examples by the encoder in one stroke (`@` is matrix multiply, `.T` transposes). The four lines computing `gWd` and `gWe` *are* backpropagation for this two-layer net: the chain rule, written out, multiplying local slopes layer by layer.]

#keyidea[
The tinyzip sketch makes the abstract concrete: a learned transform is just weights, and gradient descent *finds* the weights that decorrelate the data — the same job the DCT and PCA do by hand, now done automatically against a reconstruction loss. Add the rate term to the loss, and gradient descent will also learn to make the latent *cheap to entropy-code*, not merely accurate. That is the leap from "autoencoder" to "codec."
]

== Where learned compression stands, mid-2026

We close with an honest ledger, because hype is a poor guide to deployment. Learned codecs *win decisively* on perceptual quality at *low bitrate*: when bits are scarce, a generative decoder that reconstructs plausible texture beats any block-transform codec that can only blur. They now *match or exceed* the best hand-built standards on standard metrics — Minnen 2018 beat BPG; JPEG AI (ISO/IEC 6048-1:2025) reports up to about 28.5% smaller files than VVC-intra at equal quality. They are *flexible*: one architecture retargets to a new domain by retraining, and JPEG AI even codes a latent that machines can run object-detection on *without fully decoding the image* — compression serving machine vision, not just human eyes.

They *lose*, for now, on three fronts. *Speed*: context-model decoders can be tens of times slower than classical ones, and they lack the precious encode/decode asymmetry that makes streaming work — HEVC and AV1 decode hundreds of times faster than they encode, while neural codecs are roughly symmetric and slow on *both* ends (the 2025 one-step-distillation push is the direct response). *Hardware*: they demand GPUs or neural accelerators absent from most playback chips, raising real energy questions. *Reproducibility*: a bit-exact match between an encoder and a decoder on different machines requires identical floating-point arithmetic, a notorious headache that classical integer codecs simply do not have. The bellwether is standardization, and there the needle has moved: JPEG AI is now a published international standard. Whether neural codecs displace AV1 and VVC in the wild hinges less on rate–distortion curves — that battle is being won — and more on silicon, power budgets, and the slow grind of deployment.

#takeaways((
  [A *neuron* is a weighted sum plus a bias passed through a nonlinear *squash*; a *layer* is a matrix multiply plus a bias vector plus a squash; a *network* is layers stacked. All the intelligence lives in the weight *values*.],
  [The *universal approximation theorem* says a wide enough network can mimic any continuous function — the license to *learn* a transform instead of designing one.],
  [*Gradient descent* finds good weights by repeatedly stepping downhill on the error landscape; *backpropagation* (the chain rule, run backward) computes every gradient in about two network passes.],
  [An *autoencoder* squeezes data through a narrow *bottleneck* and back; the bottleneck forces it to learn a compact code — a narrow autoencoder *is* a lossy compressor.],
  [Real codecs add *quantization* (the lossy step), the *quantization-as-noise* trick (so gradients can flow through rounding), and a *learned entropy model* that counts the bits.],
  [Learned compression minimizes one *rate–distortion loss* $R + lambda D$ — provably the *variational-autoencoder* objective — so compression is variational inference and every generative advance is a potential compression advance.],
  [The four generative families — *autoregressive*, *VAE*, *GAN*, *diffusion* — are four ways to learn the source distribution $p(x)$, each convertible into a compressor with a different speed/quality/faithfulness profile.],
  [By 2025 a learned codec (JPEG AI, ISO/IEC 6048-1:2025) became the first learning-based *international standard*, beating VVC — but learned codecs still lag on speed, hardware, and reproducibility.],
))

== Exercises

#exercise("56.1", 1)[
A single neuron has weights $bold(w) = (2, -1, 0.5)$ and bias $b = -1$, and uses the ReLU squash. Compute its output for the input $bold(x) = (1, 3, 4)$. Then compute it for $bold(x) = (0, 0, 0)$.
]
#solution("56.1")[
Weighted sum for $(1,3,4)$: $2(1) + (-1)(3) + 0.5(4) + (-1) = 2 - 3 + 2 - 1 = 0$. ReLU of $0$ is $0$. For $(0,0,0)$: the weighted sum is $0 + 0 + 0 + (-1) = -1$; ReLU clamps negatives to $0$, so the output is $0$ again. (Both happen to be zero — a reminder that ReLU is "off" for any input whose weighted sum lands at or below zero.)
]

#exercise("56.2", 1)[
Explain in one or two sentences why stacking two *linear* layers (no squash) gives no more representational power than a single linear layer. What property of the squash breaks this collapse?
]
#solution("56.2")[
Two linear layers compute $W_2(W_1 bold(x) + bold(b)_1) + bold(b)_2 = (W_2 W_1) bold(x) + (W_2 bold(b)_1 + bold(b)_2)$, which is itself one linear map $W' bold(x) + bold(b)'$ — no gain. The squash is *nonlinear*, so it cannot be absorbed into the surrounding matrices; it lets each layer bend the input in a way the next layer can build on, which is what gives depth its power.
]

#exercise("56.3", 2)[
A weight $w$ currently sits at $w = 3$, and the gradient of the loss with respect to it is $(partial L)\/(partial w) = +4$ (the loss *increases* as $w$ increases). With learning rate $eta = 0.1$, give the updated value of $w$ after one gradient-descent step. In which direction did $w$ move, and why is that the right direction to shrink $L$?
]
#solution("56.3")[
Update rule: $w ← w - eta (partial L)\/(partial w) = 3 - 0.1 times 4 = 3 - 0.4 = 2.6$. The weight *decreased*. The gradient is positive, meaning $L$ rises as $w$ rises; to *reduce* $L$ we must move $w$ the *opposite* way — downhill — which is exactly what subtracting $eta times "gradient"$ does. The learning rate $eta$ controls how big the step is.
]

#exercise("56.4", 2)[
In the rate–distortion loss $cal(L) = R + lambda D$, describe what happens to the trained codec as $lambda → infinity$ and as $lambda → 0$. Which regime gives small files, and which gives faithful reconstructions? Tie your answer to the rate–distortion curve of Chapter 21.
]
#solution("56.4")[
As $lambda → infinity$ the distortion term dominates, so the optimizer cares almost only about reconstruction quality and will spend bits freely: *large files, faithful (low-distortion) reconstructions* — the high-rate, low-distortion end of the curve. As $lambda → 0$ the rate term dominates and the optimizer minimizes file size at the expense of quality: *tiny files, blurry/high-distortion reconstructions* — the low-rate end. Sweeping $lambda$ from large to small traces the codec's operating points along the rate–distortion frontier of Chapter 21, each $lambda$ picking one point.
]

#exercise("56.5", 2)[
The chain rule: let $a = 2x$, $b = a^2$, and $L = b + 5$. Use the chain rule to compute $(d L)\/(d x)$ as a function of $x$, then evaluate it at $x = 3$.
]
#solution("56.5")[
Local slopes: $(d a)\/(d x) = 2$; $(d b)\/(d a) = 2a$; $(d L)\/(d b) = 1$. Multiply along the chain: $(d L)\/(d x) = (d L)\/(d b) dot (d b)\/(d a) dot (d a)\/(d x) = 1 dot 2a dot 2 = 4a = 4(2x) = 8x$. At $x = 3$: $8 times 3 = 24$. (Backpropagation is just this multiplication of local slopes, done backward and reused across all weights.)
]

#exercise("56.6", 2)[
Why does rounding (quantization) break gradient descent, and how does the "quantization-as-noise" trick fix it during training? What is replaced by what, and why does the replacement have the right *spread*?
]
#solution("56.6")[
Rounding $hat(y) = round(y)$ is a staircase: flat between half-integers (slope $0$ everywhere it is defined) with undefined jumps. A zero gradient tells backpropagation "changing $y$ doesn't change the output," so no learning signal flows through the quantizer — training stalls. The fix replaces hard rounding, *during training only*, with adding uniform noise $u$ drawn evenly from $(-1\/2, +1\/2)$: $hat(y) approx y + u$. This is smooth (gradients flow) and its spread of $plus.minus 1\/2$ matches the actual error that real rounding introduces (a value can be off by up to half a step), so the network trains against a faithful, differentiable stand-in for quantization. At test time you switch back to true rounding.
]

#exercise("56.7", 3)[
*Coding.* Modify the tinyzip Step 21 sketch so the data is *triples* of correlated pixels $(a, a, a)$ plus small noise, compressed through a *single* latent number ($d = 3$, `latent = 1`). Before running, predict the rough form of the learned encoder row, then state what compression ratio (input numbers to latent numbers) the bottleneck achieves and why the MSE stays small.
]
#solution("56.7")[
Change the data generator to `data = np.hstack([a + 0.05*rng.normal(size=(2000,1)) for _ in range(3)])` and call `train_autoencoder(data, latent=1, eta=0.2)` — a *smaller* learning rate, because with three inputs the original $eta = 0.5$ takes steps so large the loss overflows to infinity (a vivid demonstration of the Pitfall above: too big a step and gradient descent diverges instead of descending). *Prediction:* since all three pixels share the same underlying value $a$, the smart code is again their average, so the learned encoder row should come out roughly proportional to $(1, 1, 1)$ (each pixel contributing equally). *Compression ratio:* three input numbers are represented by one latent number, a $3:1$ ratio. *Why MSE stays small:* the three pixels are nearly identical, so one number (their shared value) reconstructs all three almost perfectly; the only error is the tiny per-pixel noise the bottleneck cannot recover. This is the same principle as transform coding (Chapter 38): concentrate the energy into few coefficients and drop the rest.
]

== Further reading

- Diederik Kingma and Max Welling (2013), _Auto-Encoding Variational Bayes_ — the VAE: #link("https://arxiv.org/abs/1312.6114")[arXiv:1312.6114].
- Ian Goodfellow et al. (2014), _Generative Adversarial Networks_: #link("https://arxiv.org/abs/1406.2661")[arXiv:1406.2661].
- Jonathan Ho, Ajay Jain, Pieter Abbeel (2020), _Denoising Diffusion Probabilistic Models_: #link("https://arxiv.org/abs/2006.11239")[arXiv:2006.11239].
- David Rumelhart, Geoffrey Hinton, Ronald Williams (1986), _Learning representations by back-propagating errors_, *Nature* 323, 533–536.
- Johannes Ballé, Valero Laparra, Eero Simoncelli (2017), _End-to-End Optimized Image Compression_: #link("https://arxiv.org/abs/1611.01704")[arXiv:1611.01704].
- Yibo Yang, Stephan Mandt, Lucas Theis (2023), _An Introduction to Neural Data Compression_: #link("https://arxiv.org/abs/2202.06533")[arXiv:2202.06533] — the survey to read next.
- JPEG committee (2025), _JPEG AI becomes an International Standard_ (ISO/IEC 6048-1:2025): #link("https://jpeg.org/items/20250219_press.html")[jpeg.org press release].

#bridge[
We now own the entire vocabulary — neurons, gradient descent, the autoencoder, the rate–distortion loss, and the four generative families. Chapter 57 spends all of it at once. We build the *real* learned image codec: the Ballé line (2016–2018), with its end-to-end rate–distortion training, the GDN nonlinearity, quantization-as-noise made rigorous, and the *hyperprior* — a second little autoencoder that transmits a description of the entropy model itself, letting the codec adapt its bit-allocation pixel by pixel. That is the architecture that overtook JPEG, BPG, and AVIF, and became JPEG AI. Bring the bottleneck; we are about to make it pay for its bits.
]

