---
title: "Learning Solvent Effects from Transient Flow Data — My Journey in the Catechol Benchmark Hackathon"
date: 2026-01-17
draft: false
featuredImage: "featured.png"
tags: ["machine learning", "chemistry", "solvent effects", "ensembles", "Kaggle"]
categories: ["Research", "Scientific Machine Learning"]
summary: "A scientific narrative of how I built and validated a template-compatible ensemble model for the Catechol Benchmark Hackathon: from baselines to hybrid blending, symmetry-aware mixture handling, and RDKit-based molecular representations."
---

## Motivation: why solvent effects are a difficult ML problem

Solvents are not just “background”: they reshape polarity, hydrogen bonding, stabilization of transition states, and even reaction pathways.  
From a modeling perspective, this makes solvent effects hard because they are **contextual** and often **nonlinear**.

The **Catechol Benchmark Hackathon** is an elegant challenge built around that question:

> *Can a machine-learning model learn solvent effects from limited transient flow data — and generalize to unseen solvents and unseen operating ramps?*

The benchmark is small enough to run quickly, but difficult enough to punish naive modeling.
The key is not brute-force scaling — it is **representation**, **generalization**, and **evaluation discipline**.

---

## The evaluation protocol shaped everything I did

The most important lesson from this benchmark is that **evaluation is part of the problem statement**.

The competition uses a cross-validation procedure with two tasks:

### Task 1 — Single-solvent generalization
- **leave-one-solvent-out**
- meaning: an entire solvent is removed from training and used as a test fold  
- goal: learn “chemical similarity”, not memorize solvent identity

### Task 2 — Mixed-solvent generalization
- **leave-one-ramp-out**
- meaning: entire transient ramps are unseen during training  
- goal: generalize across dynamic experimental regimes

Because the benchmark score is computed through those splits, the model must be honest:
it must survive systematic out-of-distribution tests.

---

## First baselines: simple models that *looked good*… until they didn’t

My first attempts were “standard ML”:

- concatenate descriptors + operating conditions  
- train **XGBoost / LightGBM**
- tune hyperparameters aggressively

These models looked strong on small validation slices, but collapsed in the real CV protocol.
The failure mode was consistent:

> the model was learning **solvent identity shortcuts** instead of **solvent relationships**.

This was the point where I stopped tuning blindly and started working backwards from the evaluation objective.

---

## A turning point: mixtures should obey symmetry

Mixtures introduced a subtle but critical constraint:

If the experiment contains Solvent A + Solvent B at fraction *p*, then:

- swapping A and B
- and replacing *p* by *(1 − p)*

should not change the chemistry.

Many tabular models do **not** respect this symmetry automatically.
So I enforced it explicitly by building a workflow that treats:

- (A, B, p) and (B, A, 1−p)

as equivalent representations during training and prediction.

This single idea reduced variance noticeably in mixture folds.

---

## Building representations: why chemistry features matter more than model size

At this stage, I started treating solvent modeling as a representation-learning problem:

> the model should “see” that similar solvents are close, and mixtures are convex combinations.

I explored multiple feature families.

### 1) Precomputed descriptors (benchmark-provided)
These are strong baselines and very practical:

- SPANGE descriptors  
- ACS PCA descriptors  
- DRFP-based fingerprints  
- Fragprints

They are consistent, fast, and proven — a good foundation.

### 2) RDKit Morgan fingerprints (ECFP-like)
Morgan fingerprints capture substructure neighborhoods around atoms.
They often help when the dataset is small but chemical diversity matters.

To keep them trainable in CPU-only settings, I compressed them using:
- **Truncated SVD** (dimension reduction)
- then standard scaling

This created a compact “solvent vector” that is both expressive and stable.

### 3) MACCS keys (RDKit)
MACCS keys are a classic compact fingerprint: a curated set of structural keys.
They are not always the strongest representation, but they are:
- lightweight
- interpretable
- often useful as a “regularizer-like” signal in ensembles

### 4) Mordred descriptors (optional)
Mordred provides a large set of molecular descriptors:
topological indices, constitutional descriptors, charge-like proxies, etc.

It is powerful, but in small-data settings it can easily introduce:
- redundancy
- high correlation
- overfitting

So I treated Mordred as something to integrate cautiously:
it is a strong *candidate feature family*, but requires careful pruning.

---

## My final strategy: two complementary branches + hybrid blending

After many iterations, my best performing solution became a hybrid ensemble:

### Model A — “Learned solvent vector branch”
This branch builds a continuous solvent embedding (`SOLV_VEC`) by combining:

- SPANGE + ACS descriptors
- DRFP + Fragprints (compressed with SVD)
- RDKit Morgan fingerprints (compressed with SVD)

Then it uses multiple learners:

- a small **MLP**
- **XGBoost**
- **LightGBM**

and blends them into one prediction.

This model tends to generalize well to **unseen solvents**, because solvent similarity is encoded in the representation.

---

### Model B — “Correlation-filtered chemistry table branch”
This branch focuses on stability and low-noise learning:

- build a large descriptor table  
- remove constant columns  
- remove highly correlated features (with simple priority rules)

Then train:

- **CatBoost** (MultiRMSE objective)
- **XGBoost** (one regressor per target)

and blend predictions **per target**.

This model is often more stable for certain targets and folds.

---

## Why hybrid blending worked better than choosing a single “best” model

Neither branch dominated everywhere.

- Model A was good at **solvent similarity**
- Model B was good at **robustness under limited folds**

So I blended them:

\[
P = w_A \cdot P_A + (1-w_A)\cdot P_B
\]

Instead of tuning endlessly, I used a simple “sanity pipeline” to evaluate a small set of candidate weights.
This approach produced stable improvements without overfitting.

In my final runs, I used:
- a lower weight for Model A in the single-solvent task
- a higher weight for Model A in the mixture task  
because mixture symmetry + solvent vector interpolation mattered more.

---

## Experiment diary: what I tried (and what I learned)

### ✅ What improved performance
- enforcing mixture symmetry (swap augmentation)
- keeping representations compact (SVD / filtering)
- per-target blending (some targets benefit from different bias–variance tradeoffs)
- respecting the competition CV design (not optimizing on the wrong split)

### ❌ What failed (and why it was useful anyway)
- too many descriptors without pruning (especially Mordred)  
  → higher variance and unstable folds  
- heavy hyperparameter search  
  → “local improvements” that did not survive the real CV protocol  
- using one model for everything  
  → different targets respond differently to bias and noise

---

## Engineering constraints: making everything submission-compatible

The competition notebook required one strict rule:

> the **last three cells** must match the official template,  
> and only the `model = ...` line is allowed to change.

That forced me to treat reproducibility as part of the solution:
- no hidden dependencies
- predictable training per fold
- stable feature construction
- careful CPU runtime management

I also hit realistic “research engineering” bugs — such as dtype mismatches between Float32 and Float64 in PyTorch —
which reminded me that *getting the pipeline to run reliably* is a scientific contribution on its own.

---

## Final outcome (and why I’m satisfied)

My best submission reached:

- **rank ~26 / 227**
- strong mean RMSE under the official evaluation protocol

But what mattered more than the rank was the scientific clarity I gained:

> In small-data scientific ML, performance comes from respecting structure:  
> chemistry representations, symmetry, and honest evaluation.

---

## References

- Catechol Benchmark (paper / benchmark description):
  - https://arxiv.org/abs/2512.19530

- RDKit fingerprints (Morgan / MACCS):
  - https://www.rdkit.org/

- Mordred descriptor calculator:
  - https://doi.org/10.1186/s13321-018-0258-y

- DRFP (Differential Reaction Fingerprint):
  - https://www.digitaldiscoveryjournal.org/

---

## Closing note

This benchmark was one of the most educational projects I have done recently,
because it rewarded scientific thinking more than “bigger models”.

It was a reminder that machine learning, when applied to chemistry,
works best when we treat **representation, invariance, and evaluation**
as first-class citizens — not afterthoughts.


