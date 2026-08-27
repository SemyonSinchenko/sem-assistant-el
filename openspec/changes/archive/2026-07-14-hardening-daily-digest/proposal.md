# Proposal: Analyze and fix daily digest errors

## Intent
There are some reare errors:
* TODO [2026-05-19 09:32:46] [llm] [ERROR] FAIL
DEADLINE: <2026-05-19 Tue 09:32>
:PROPERTIES:
:CREATED: [2026-05-19 09:32:46]
:END:
Error: Callback error: Invalid use of ‘\’ in replacement text

** Input
You are a Research Assistant monitoring arXiv preprints.
Target Audience: Graph & Data Systems Researcher.
Language: Russian.
Output Format: Org-mode.

Context:
Focus on Databases, Distributed Systems, Graph Algorithms, Network Analysis, and applied ML for systems.

CRITICAL OUTPUT RULES:
- Return ONLY raw Org-mode text.
- Do NOT use markdown, code fences, XML/JSON wrappers, or any commentary.
- Start directly with the first Org heading.
- Follow Org heading syntax strictly.

Task:
1. Group papers by arXiv categories: cs.DB (Databases), cs.AI (Artificial Intelligence), physics.soc-ph (Social Physics & Networks), cs.DS (Data Structures & Algorithms), cs.DC (Distributed Computing).
2. For each non-empty category, generate the following structure:

* <Category Name>
** 🧐 Обзор
2-4 sentences on trend for the last 1 days: what is new, what is maturing, what is practically relevant.

** 🛠 Практика и Системы
- [[<Link>][<Title>]]
:WHAT: What system/optimization/method is introduced.
:IMPACT: Why it matters in practice.

** 🕸 Графы и Алгоритмы
- [[<Link>][<Title>]]
:ALGO: Key algorithmic or modeling contribution.
:IMPACT: Why it matters for graph/data systems.

** 📄 Остальное
- [[<Link>][<Title>]] — one concise sentence.

Selection constraints:
- Prioritize papers with clear system impact or strong algorithmic contribution.
- Deprioritize purely theoretical work unless it has plausible practical/system relevance.
- Omit empty subsections if no papers match.
- Omit empty categories.

Data:
Title: Compass: SLO-aware Query Planner for Compound AI Serving at Scale
Link: https://arxiv.org/abs/2504.16397
Tags: arxiv, csdb
Abstract/Content: arXiv:2504.16397v2 Announce Type: replace Abstract: The rise of compound AI serving that integrates multiple operators in a pipeline enables end-user applications such as generative AI-powered meeting companions, autonomous driving, and immersive gaming. These workloads span diverse deployment spaces, from cloud-only queries to edge-assisted ones across infrastructure tiers, often including both within an application. Achieving high service goodput -- i.e., meeting service level objectives (SLOs) for pipeline latency, accuracy, and costs -- requires joint planning of operators' placement, configuration, and resource allocation. However, diverse SLOs, varying runtime environments (e.g., heterogeneous device speeds), and a large volume of queries competing for shared infrastructure explode the planning space, making real-time serving and cost-efficient deployment intractable with existing advances. This paper presents Compass, the first SLO-aware query planner that optimizes large-scale compound AI workloads across diverse deployment spaces. Compass decomposes the many-query, multi-SLO planning problem into tractable subproblems while preserving global decision quality, exploiting plan similarities within and across queries to slash the search steps. It further improves per-step efficiency with a plan profiler that performs selective profiling to achieve high-fidelity performance estimates at a fraction of the profiling cost. At runtime, Compass performs query-plan bipartite matching to maximize SLO goodput under resource contentions. Real-world evaluations show that Compass improves service goodput by 2.4--5.1x, reduces deployment costs by 3.8--4.5x, and accelerates planning by 4.2--10.5x, achieving service responsiveness within seconds and near-optimal decision quality.
---

Title: LSM-VEC: A Large-Scale Disk-Based System for Dynamic Vector Search
Link: https://arxiv.org/abs/2505.17152
Tags: arxiv, csdb
Abstract/Content: arXiv:2505.17152v2 Announce Type: replace Abstract: Vector search underpins modern AI applications by supporting approximate nearest neighbor (ANN) queries over high-dimensional embeddings in tasks like retrieval-augmented generation (RAG), recommendation systems, and multimodal search. Traditional ANN search indices (e.g., HNSW) are limited by memory constraints at large data scale. Disk-based indices such as DiskANN reduce memory overhead but rely on offline graph construction, resulting in costly and inefficient vector updates. The state-of-the-art clustering-based approach SPFresh offers better scalability but suffers from reduced recall due to coarse partitioning. Moreover, SPFresh employs in-place updates to maintain its index structure, limiting its efficiency in handling high-throughput insertions and deletions under dynamic workloads. This paper presents LSM-VEC, a disk-based dynamic vector index that integrates hierarchical graph indexing with LSM-tree storage. By distributing the proximity graph across multiple LSM-tree levels, LSM-VEC supports out-of-place vector updates. It enhances search efficiency via a sampling-based probabilistic search strategy with adaptive neighbor selection, and connectivity-aware graph reordering further reduces I/O without requiring global reconstruction. Experiments on billion-scale datasets demonstrate that LSM-VEC consistently outperforms existing disk-based ANN systems. It achieves higher recall, lower query and update latency, and reduces memory footprint by over 66.2%, making it well-suited for real-world large-scale vector search with dynamic updates.
---

Title: Factual Inconsistencies in Multilingual Wikipedia Tables
Link: https://arxiv.org/abs/2507.18406
Tags: arxiv, csdb
Abstract/Content: arXiv:2507.18406v2 Announce Type: replace-cross Abstract: Wikipedia serves as a globally accessible knowledge source with content in over 300 languages. Despite covering the same topics, the different versions of Wikipedia are written and updated independently. This leads to factual inconsistencies that can impact the neutrality and reliability of the encyclopedia and AI systems, which often rely on Wikipedia as a main training source. This study investigates cross-lingual inconsistencies in Wikipedia's structured content, with a focus on tabular data. We developed a methodology to collect, align, and analyze tables from Wikipedia multilingual articles, defining categories of inconsistency. We apply various quantitative and qualitative metrics to assess multilingual alignment using a sample dataset. These insights have implications for factual verification, multilingual knowledge interaction, and design for reliable AI systems leveraging Wikipedia content.
---

Title: SonicDB S6: A Storage-Efficient Verkle Trie for High-Throughput Blockchains
Link: https://arxiv.org/abs/2604.06579
Tags: arxiv, csdb
Abstract/Content: arXiv:2604.06579v2 Announce Type: replace Abstract: The Ethereum state database uses Merkle Patricia Trie (MPT), which suffers from large witness proof sizes and high storage overhead. Verkle Tries have been proposed as a replacement, offering witness proofs below 150 bytes through vector commitments and Inner Product Argument aggregation. However, deploying a Verkle Trie in a high-throughput, short block-time blockchain such as Sonic, which produces a block every 300 milliseconds, introduces substantial engineering challenges related to storage efficiency, commitment computation costs, and the need to serve both live and historical state queries in real time. We present SonicDB S6, a production-grade Rust Verkle Trie database for the Sonic blockchain, which leverages its non-forking property to enable aggressive storage optimizations. Occupancy-aware node specializations, selected via an $\mathcal{O}(k n^2)$ dynamic program, reduce live storage by 97.8\%. Delta nodes that record only changed slots reduce archive storage by 95\%. Batched updates, multi-threaded commitment computation, and homomorphic Pedersen caching yield $3.2\times$ higher throughput than a persistent Geth Verkle baseline while sustaining production block-rate performance.
---

Title: QuIVer: Rethinking ANN Graph Topology via Training-Free Binary Quantization
Link: https://arxiv.org/abs/2605.02171
Tags: arxiv, csdb
Abstract/Content: arXiv:2605.02171v3 Announce Type: replace Abstract: Approximate nearest neighbor (ANN) graph indices such as HNSW and Vamana construct their edge topology in full-precision or high-fidelity quantized metric spaces, relegating binary quantization (BQ) to a post-hoc distance estimator during search. This paper asks a different question: Can binary quantization define the graph topology itself -- and if so, under what conditions? We study this question through QuIVer (Quantized Index for Vector Retrieval), a training-free ANN graph index that performs Vamana edge selection, diversity pruning, and beam-search navigation entirely within a 2-bit Sign-Magnitude BQ metric space, accessing float32 vectors only for final reranking. Systematic evaluation on twelve million-scale datasets reveals a sharp applicability boundary: BQ-native topology is highly effective on cosine-native contrastive-learning embeddings (>=88% Recall@10 at ef=64 across five datasets, 384--3072 dimensions), moderately effective on multimodal CLIP data (71--78%), and empirically unsuitable for Euclidean-native or structureless distributions (<15%). Our results suggest an empirical "impossible triangle" between aggressive compression, high throughput, and universal data compatibility. The central contribution is not merely the system, but the boundary it reveals: falsifiable criteria for when industrial vector search systems can safely trade metric fidelity for compact BQ-native navigation. On compatible workloads, the system benefits are substantial: QuIVer's BQ-native hot path (<1.3 GB for 1M vectors) yields 2.5--5.5x higher multi-threaded throughput than DiskANN Rust and HNSW variants at matched recall, with 4.7x less hot memory and no codebook or rotation training (unlike PQ/OPQ/RaBitQ).
---

Title: Elastic Scheduling of Intermittent Query Processing in a Cluster Environment
Link: https://arxiv.org/abs/2605.08601
Tags: arxiv, csdb
Abstract/Content: arXiv:2605.08601v2 Announce Type: replace Abstract: Many applications process a stream of tuples over a window duration, and require the results within a specified deadline after the end of the window. For such scenarios, processing tuples intermittently (in batches) instead of eagerly processing tuples as they arrive significantly reduces the overall cost. Earlier work on intermittent query processing has addressed only fixed environments. In this paper, we propose scheduling schemes for batched processing of tuples, in an elastic parallel environment, scaling nodes up or down. Our scheduling schemes ensure to meet the deadlines, while incurring minimum cost. Our schemes also handle multiple concurrent queries, the arrival of new queries, and input rate variations. We have implemented our schemes on top of Apache Spark, in the AWS EMR environment, and evaluated performance with both TPC-H and Yahoo Streaming datasets. Our experimental results show that our scheduling algorithms significantly outperform alternatives, such as using a fixed set of nodes without elasticity, or using Spark streaming.
---

Title: Machine Learning-Based Pre-Test Risk Stratification for PCR-Confirmed Chlamydia Using Patient-Reported Data and Urine Biomarkers
Link: https://arxiv.org/abs/2605.16365
Tags: arxiv, csdb
Abstract/Content: arXiv:2605.16365v1 Announce Type: cross Abstract: Early identification of individuals at elevated risk of Chlamydia trachomatis infection may enable optimal use of molecular testing in resource-aware screening. We evaluate the feasibility of pre-test risk stratification (PTRS) using machine-learning models trained on routinely available, non-invasive clinical data. A curated dataset of 93 urine samples with PCR reference labels was analyzed using three feature groups: patient-reported history and symptoms, urine biomarkers from standard urinalysis, and their combination. Five supervised classifiers were evaluated using stratified 5-fold cross-validation with out-of-fold probability estimates. Performance was assessed using area under the receiver operating characteristic curve (AUC) and threshold-dependent metrics, with uncertainty quantified via bootstrap confidence intervals. Models using only patient-reported data showed moderate discrimination (AUC up to 0.72). Urine biomarker-based models demonstrated slightly lower peak discrimination but more consistent performance, with ensemble methods yielding the strongest results. Combining feature groups marginally increased the peak AUC and reduced performance variability across models, indicating improved robustness. Findings indicate that urine biomarkers provide a reliable predictive signal for PTRS that is complementary to patient-reported information, while feature integration enhances robustness. This work supports the integration of non-invasive, routinely available information for PTRS into screening workflows, including decentralized or home-based PCR contexts, to optimize testing prioritization.
---

Title: Revisiting the Maximum Defective Clique Problem: Faster Branching and a Tighter Upper Bound
Link: https://arxiv.org/abs/2605.16948
Tags: arxiv, csdb
Abstract/Content: arXiv:2605.16948v1 Announce Type: new Abstract: The $k$-defective clique model relaxes the strict completeness constraint of the traditional clique by allowing up to $k$ missing edges, providing a robust formulation for detecting cohesive structures in noisy graphs. Consequently, the maximum $k$-defective clique problem has attracted significant attention. State-of-the-art exact algorithms predominantly adopt the branch-and-bound framework, which recursively partitions the current problem instance (or branch) into two sub-problems via a branching procedure, until each sub-problem becomes trivially solvable. However, this strategy often leads to excessive branching by overlooking intermediate sub-problems that are non-trivial yet efficiently solvable. While recent studies have attempted to refine branching procedures, they fail to address this structural redundancy. To address this, we propose BBRes, a framework that incorporates a novel early termination strategy into the recursive branching process. By employing a specialized polynomial-time solver to identify and resolve tractable sub-instances, BBRes effectively avoids redundant branching steps. Additionally, we design a tailored branching strategy that synergizes with this termination mechanism. As a result, BBRes achieves an improved theoretical worst-case time complexity. To enhance practical performance, we propose a tighter upper bound based on a novel double graph coloring method integrated with max-flow techniques, which is orthogonal to the branching framework. Extensive experiments show that BBRes achieves at least 2X speedup over state-of-the-art methods on a substantial fraction of the datasets.
---

Title: Coordinate Heterogeneity Governs Binary Quantization: From InfoNCE to Recall
Link: https://arxiv.org/abs/2605.17524
Tags: arxiv, csdb
Abstract/Content: arXiv:2605.17524v1 Announce Type: cross Abstract: Binary quantization (BQ) compresses high-dimensional embeddings into one or two bits per coordinate, enabling nearest neighbor search at extreme speed. Yet a striking puzzle persists: BQ achieves competitive recall on contrastive embeddings but fails on others -- and two leading systems adopt diametrically opposite strategies (random rotation vs. preserving coordinate axes) without a common theory explaining when each is appropriate. We resolve this puzzle by connecting the Gaussian structure recently established for InfoNCE-trained representations to a complete analytical framework for BQ quality. The key insight is that coordinate heterogeneity -- the non-uniformity of per-coordinate variances -- governs the key aspects of BQ performance. We derive closed-form expressions for ranking fidelity, prove that the magnitude bit carries information proportional to heterogeneity, and show that random rotation destroys precisely the signal that one paradigm exploits while creating the isotropy that the other requires. A two-parameter scaling law predicts fidelity across models and dimensions. Experiments on 13 datasets and 6 embedding families validate all predictions and provide the first principled design guide for binary quantization systems.
---

Title: General Science Ranking (GSR): An Open-Source, Citation-Normalized Journal and Conference Classification System for Computer Science and Medicine
Link: https://arxiv.org/abs/2605.17657
Tags: arxiv, csdb
Abstract/Content: arXiv:2605.17657v1 Announce Type: cross Abstract: The academic journal zoning system is central to evaluating research talent, funding, and institutions. The CAS journal partition system, one of East Asia's most widely used tools, will cease operation in March 2026, creating a policy gap. Existing alternatives have major limitations: JCR depends on paid databases and excludes conferences; Scimago/CiteScore relies on Elsevier proprietary data; expert-based rankings such as CCF and CORE lack quantitative foundations and update slowly. This paper proposes the General Science Ranking (GSR), a multidimensional bibliometric framework built entirely on open-source data. GSR covers 500 computer science venues (397 journals and 103 conferences) and 500 medical journals using OpenAlex and Semantic Scholar. Scores combine four indicators: field-weighted citation impact (FWCI), two-year impact factor (IF2), five-year h-index (h5), and citation CAGR. For CS conferences lacking citation time-series data, IF2-approx was estimated from calibration on 1.41 million OpenAlex journal papers. Rankings adopt fixed quotas: Q1 (1-50), Q2 (51-100), Q3 (101-200), and Q4 (201+). All code and data are open source. In CS rankings, conferences and journals each occupy 25 of the top 50 Q1 positions. The leading conferences are NeurIPS, ICCV, ICLR, and CVPR. In medicine, CA: A Cancer Journal for Clinicians ranks first, followed by New England Journal of Medicine and The Lancet. Agreement with JCR Q1 reaches 84 percent in medicine and 71 percent in CS. Sensitivity analysis shows only 1.7 percent to 2.5 percent of CS conferences change partitions, indicating robustness. GSR provides a free, reproducible, field-normalized ranking system covering both journals and conferences, making it suitable for institutional evaluation policies.
---

Title: Endogenous Feedback in Coevolutionary Games Reshapes the Stability of Cooperation
Link: https://arxiv.org/abs/2506.20603
Tags: arxiv, socph
Abstract/Content: arXiv:2506.20603v2 Announce Type: replace Abstract: In Evolutionary game theory the payoffs are typically fixed or shaped by external environmental variables. Here, we introduce an endogenous-feedback model in which the game played coevolves directly with the population state: the payoff matrix is a time-dependent function of the level of cooperation. This allows strategic incentives to be continuously modified by the collective behavior they generate. Even in the simplest case of linear and instantaneous feedback, the model reveals feedback-induced regimes, termed chimera games, in which stable cooperation arises despite being incompatible with the predictions of standard fixed-game dynamics. We further show that delayed feedback can destabilize these equilibria and generate sustained oscillations, while nonlinear feedback reshapes equilibrium structure and introduces path dependence. Our results show how cooperation can be promoted, suppressed, or destabilized by incentives generated endogenously by the very same population's collective behavior. We conclude by outlining how our framework connects to real-world systems shaped by endogenous feedback.
---

Title: CARDIO-Affect: A Hamiltonian-Variability Framework for Spatio-Temporal Emotional Pattern Recognition with Manifold-Based Individual and Group Profiling
Link: https://arxiv.org/abs/2510.16046
Tags: arxiv, socph
Abstract/Content: arXiv:2510.16046v3 Announce Type: replace Abstract: We present CARDIO-Affect, a complex-systems theoretical framework for long-term emotional dynamics in bounded social groups, with explicit uncertainty quantification at every layer. Long-period naturalistic emotion in stable small groups exhibits hallmarks of complex systems -- multi-stable attractors, weak chaos, long-range memory, and sparse heterogeneous coupling -- invisible to conventional short-clip facial-emotion analysis. CARDIO-Affect treats individual emotion as a multi-stable nonlinear stochastic dynamical system and group emotion as a sparsely-coupled network with emergent macrostates, formalised through six propositions and four pillars: (i) statistical mechanics with neural-parameterised Hamiltonian SDE over asymmetric potentials; (ii) information geometry on a 45-dimensional Fisher-Rao manifold; (iii) topological data analysis for invariant trajectory signatures; (iv) HRV-inspired Emotional Variability Analytics (EVA) decomposing each person-day into multi-scale time/frequency/nonlinear measures. We validate on the first 30.1-month longitudinal in-the-wild facial-emotion corpus (companion: arXiv:2510.15221) by discovering three falsifiable paradoxes: Sparse-Contagion (R_0=0.36, density 2.7%, 8 BH-FDR edges), Asymmetric-Persistence (negative dwell 5.85x positive, 1.77D potential gap), and Crisis-Inversion (Shanghai 2022 lockdown naive d=-0.40 collapses to permutation-p=0.94 under BSTS + synthetic-control). On synthetic benchmarks, CARDIO-EBM v2 matches asymptotically optimal Granger on linear VAR data (Class A AUROC 0.984+/-0.012 vs Granger 0.997+/-0.001, 5 seeds) but fails on tanh-coupled nonlinear data (Class B AUROC 0.490 vs Granger 0.796), a documented limitation of the linear mask-self estimator. We release framework code and the full reproduction pipeline.
---

Title: City-level energy and emission assessment based on 20+ million electric vehicle registrations in China
Link: https://arxiv.org/abs/2511.20742
Tags: arxiv, socph
Abstract/Content: arXiv:2511.20742v4 Announce Type: replace Abstract: China, the world's largest electric vehicle (EV) market, plays a pivotal role in global decarbonization of the transport sector. We present the first high-resolution assessment of EV adoption in 295 cities, utilizing more than 20 million registrations of 586 EV models tracked monthly from 2022 to 2024 and projecting transition pathways to 2035. Real-world data reveal that EVs are 30.9-212.8 megajoules per 100 km more energy efficient than internal combustion vehicles, yet their carbon intensities range from 18.2 to 270.4 gCO2/km among provinces. The limited electrification of hybrids means that gasoline still accounts for 44% of EV energy use. Scenario projections suggest that emissions will peak about 2030 at 21.1-30.9 megatonnes of CO2 and decline by 2035 under continued market transition. The findings establish an empirical foundation for accurate emissions accounting, emphasize the need to reduce regional disparities in adoptability, and offer globally relevant insights for road-transport decarbonization.
---

Title: On the Meaning of Urban Scaling
Link: https://arxiv.org/abs/2603.30021
Tags: arxiv, socph
Abstract/Content: arXiv:2603.30021v2 Announce Type: replace Abstract: Cities are often compared through scaling laws, usually expressed as power-law relations between population size and aggregate urban quantities related to infrastructure, socioeconomic activity, or environmental impacts. These laws are influential because their exponent is often interpreted as describing what happens when a city grows, with implications for urban theory, planning, and policy. Here, we show that this interpretation is generally misleading. An exponent measured by comparing many cities at one date does not, in general, describe the trajectory of any individual city. Instead, it reflects a statistical pattern produced by cities with different histories, constraints, institutions, and growth paths. Apparent sublinear or superlinear scaling can therefore arise even when individual cities follow simpler dynamics, as we show for the area--population relation. Cross-sectional scaling laws can reveal system-level regularities, but should not be used alone to infer growth mechanisms or guide policy for a given city.
---

Title: The Quiet and the Compliant: How Regulation and Polarization Shape Conventional Wisdoms on Corporate Social Engagement in High-risk Settings
Link: https://arxiv.org/abs/2604.06223
Tags: arxiv, socph
Abstract/Content: arXiv:2604.06223v2 Announce Type: replace Abstract: With the international business landscape becoming more crisis-ridden as risks proliferate, how do the professionals who implement corporate social initiatives in high-risk environments perceive their work, and what can this reveal about the forces shaping business engagement with society in crisis contexts? We present findings from a synthetic survey of 400 corporate professionals working on social impact in fragile and conflict-affected settings to understand conventional wisdoms and best practices on corporate strategy and activity in high-risk settings. Drawing on political corporate social responsibility (CSR), synthetic survey, and international business literatures, we test seven hypotheses about how regulatory environments, political polarization, sector characteristics, and organizational structures shape corporate social engagement in high-risk contexts. The synthetic results suggest that European professionals report significantly higher strategic integration of social impact across all measured dimensions, while US professionals overwhelmingly report that political polarization hinders social initiatives, yet this perception does not predict unreported social activities, complicating the emerging "quiet CSR" narrative. Extractive industry professionals deliver both the highest operational preparedness and the highest complicity awareness, a pattern we conceptualize as presence-dependent reflexivity. These patterns deliver a baseline to detect the theorized dynamics and offer preliminary theoretical propositions for future real-world empirical testing.
---

Title: From Particles to Policy: Technical Building Blocks for Multi-State SAI Coordination
Link: https://arxiv.org/abs/2605.14947
Tags: arxiv, socph
Abstract/Content: arXiv:2605.14947v2 Announce Type: replace-cross Abstract: Stratospheric aerosol injection (SAI) is a solar radiation modification technique, proposed as an interim measure to offset warming while greenhouse gas (GHG) emissions are reduced. This paper discusses a possible SAI implementation route - an alternative to sulfate aerosols formed in situ - based on engineered solid particles having dedicated properties such as size, composition, surface chemistry, and traceable origin, supporting safety, controllability, and functionality needed for SAI systems. These engineered properties also open up options for any future multi-state coordination of SAI through two technical building blocks: (1) the SAI-induced radiative forcing (SRF) - the magnitude of the cooling effect attributable specifically to the SAI layer - as an operator-independent quantity, derivable from direct aerosol-layer measurements; and (2) particle traceability through identifying signatures embedded at production. Both could feed into a shared, publicly accessible monitoring database open to independent interrogation, addressing several governance challenges by anchoring compliance assessments in measurable parameters. Drawing on precedents from the Montreal Protocol, IAEA safeguards, and other regimes, we show that shared technical metrics have historically enabled multi-state cooperation, and we argue the same could apply to SAI. We describe a phased pathway in which the technical capabilities and coordination practices that would use them are developed and tested together, at scales orders of magnitude below operational deployment. To be clear - we regard SAI deployment as premature; the conditions under which it might be considered have not been met. The paper does not propose a governance framework; rather, it identifies technical infrastructure that could support a wide range of such frameworks.
---

Title: Editorial Trajectories in Wikipedia Reflect Underlying Hyperlink Structure
Link: https://arxiv.org/abs/2605.16850
Tags: arxiv, socph
Abstract/Content: arXiv:2605.16850v1 Announce Type: new Abstract: Wikipedia hyperlinks have primarily been studied as navigational tools for readers, but their role in how information providers move between articles during editing remains less explored. Here, we combine the hyperlink network among English Wikipedia articles with editorial histories to examine how article-to-article structure is associated with editors' transitions between articles. We first address the temporal aspect of edit transitions by showing that transitions between hyperlinked article pairs have shorter inter-event times (IETs) than those between non-hyperlinked pairs, indicating that connected articles are effectively closer in editing sequences. We then turn to the structural organization of editing behavior by coarse-graining the hyperlink network into 19 topical communities and measuring editors' topical diversity. Finally, we bring the temporal and structural views together by comparing each editor's transition network with the corresponding hyperlink subnetwork using Jaccard similarity. Combining the measures allows us to distinguish three editor types: 'Specialists' are characterized by focused editing within limited topical domains and transition patterns more closely aligned with the hyperlink structure (low topical diversity, shorter mean IETs, and higher Jaccard similarity), whereas 'generalists' cover broader topics and show weaker similarity to the hyperlink structure (high topical diversity, longer mean IETs, and lower Jaccard similarity). 'Bots' show a distinct algorithm-driven behavior, with low Jaccard similarity and the shortest mean IETs, a combination departing from human-editor patterns despite their often high topical diversity. Such findings demonstrate that the hyperlink structure is not just a static scaffold for reader navigation, but is observationally linked to the sequential organization of editorial activity in collaborative knowledge systems.
---

Title: The Curious Case of Max Planck retracted papers. When past scientific practices meet contemporary publishing norms
Link: https://arxiv.org/abs/2605.17534
Tags: arxiv, socph
Abstract/Content: arXiv:2605.17534v1 Announce Type: cross Abstract: This article examines the case of two papers published in Naturwissenschaften by the physicist Max Planck that were retrospectively marked as retracted on Springer digital platform. Rather than originating in scientific fraud, these withdrawals appear to result from contemporary digitization and copyright-management procedures applied anachronistically to historical publications. Through an investigation of the circulation history of Planck 1940 and 1942 philosophical essays, the article shows that republication across multiple formats was a common and legitimate practice within the scientific publishing culture of the early 20th century. Such practices only became problematic with the later transformation of the scientific article into a countable and proprietary unit within systems of bibliometric evaluation and commercial academic publishing. This article argues that contemporary notions such as duplicate publication and self-plagiarism are historically situated categories that cannot be applied retrospectively without distorting the historical record. More broadly, the Planck case reveals how digital scholarly infrastructures controlled by large commercial publishers can limit the accessibility of the scientific past. Ironically, the original papers remain accessible today through the nonprofit digital platform Internet Archive rather than through the publisher that originally issued the journal.
---

Title: Hypergraphx-data: a repository for higher-order network data
Link: https://arxiv.org/abs/2605.18166
Tags: arxiv, socph
Abstract/Content: arXiv:2605.18166v1 Announce Type: new Abstract: The availability of network datasets advances research in network science, machine learning and related fields by enabling empirical analyses and their reproducibility, algorithm development, model validation and benchmarking. Existing repositories, such as SNAP and Netzschleuder, have made traditional network datasets widely accessible with metadata, metrics, and basic visualizations. However, they primarily focus on pairwise interactions, limiting data access to systems with many-body interactions. To address this gap, we created hypergraphx-data, a repository of real-world hypergraph datasets for higher-order network analysis, spanning different domains from social networks to biology and finance, and supporting configurations such as weighted, directed, temporal, and multiplex hypergraphs. Each dataset includes relational information and metadata, provided in an open JSON format and a binarized format for Hypergraphx. We provide a user-friendly interface to facilitate browsing, filtering, and accessing the datasets, while also ensuring integrity and reproducibility through hash-based verification and data versioning. The repository is available at https://hgx-team.github.io/hypergraphx-data
---

Title: The nestedness of higher-order networks
Link: https://arxiv.org/abs/2605.18420
Tags: arxiv, socph
Abstract/Content: arXiv:2605.18420v1 Announce Type: new Abstract: In contrast to dyadic interactions, higher-order interactions may contain one another, with subgroups naturally embedded within larger groups. These containment patterns arise empirically in ecology, sociology, computer science and the science of science, and have been studied under the names nestedness, simpliciality, encapsulation, and inclusion. In this chapter, we review each of these measures and unify them through a mathematical object known as the encapsulation directed acyclic graph, formulating each measure as a function of its properties. We demonstrate that nested structure is prevalent in social systems across several domains, show that different measures capture complementary aspects of this structure, and find that the absence of nestedness can itself be a powerful indicator of the mesoscale organization of a system.
---

Title: Online Resource Allocation with Convex-set Machine-Learned Advice
Link: https://arxiv.org/abs/2306.12282
Tags: arxiv, csds
Abstract/Content: arXiv:2306.12282v2 Announce Type: replace Abstract: Decision-makers often have access to machine-learned predictions about future demand that can help guide online resource allocation decisions. However, such predictions may be inaccurate. We develop a framework for online resource allocation with potentially unreliable machine-learned advice, where the advice is represented as a convex uncertainty set for the demand vector rather than a single point estimate. We introduce a parameterized class of Pareto-optimal online algorithms that balance consistency and robustness. The consistent ratio measures performance when the advice is accurate, while the robust ratio measures performance under adversarial demand when the advice is inaccurate. For a target consistency level C, our algorithms maximize robustness subject to achieving at least consistency level C. Our approach extends classical protection-level algorithms by introducing adaptive protection levels that dynamically respond to uncertainty in the advice. We also provide a method for computing the maximum achievable consistency level. Numerical experiments demonstrate that our algorithms outperform benchmark methods, including approaches based solely on point forecasts, by effectively balancing worst-case and average-case performance.
---

Title: Distance Recoloring
Link: https://arxiv.org/abs/2402.12705
Tags: arxiv, csds
Abstract/Content: arXiv:2402.12705v5 Announce Type: replace Abstract: Reconfiguration problems ask whether one feasible solution can be transformed into another by a sequence of local moves while maintaining feasibility throughout. For integers $d \geq 1$ and $k \geq d+1$, the Distance Coloring problem asks if a given graph $G$ has a $(d, k)$-coloring, i.e., a coloring of the vertices of $G$ by $k$ colors such that any two vertices within distance $d$ from each other have different colors. For ordinary proper colorings ($d=1$), the $k$-Coloring Reconfiguration problem is polynomial-time solvable for $k\le 3$ [Cereceda, van den Heuvel, and Johnson, J. Graph Theory 67(1):69--82, 2011] but is $\mathsf{PSPACE}$-complete for every fixed $k\ge 4$, even on bipartite graphs [Bonsma and Cereceda, Theor. Comput. Sci. 410(50):5215--5226, 2009]. In this work, we initiate a study of the distance-$d$ analogue, for $d \geq 2$. We show that even for planar, bipartite, and $2$-degenerate graphs, $(d, k)$-Coloring Reconfiguration remains $\mathsf{PSPACE}$-complete for every $d \geq 3$ via a reduction from the well-known Sliding Tokens problem. Our construction uses $k = k_0 + 2 + n(\lceil d/2\rceil-1)$ colors on instances of size $n$, where $k_0\in\{3d+3,3d+6\}$ (depending on the parity of $d$). For $d = 2$, the same reduction scheme can be adapted to show that the problem is $\mathsf{PSPACE}$-complete on planar and $2$-degenerate graphs with same values of $k$. Additionally, on split graphs, there is an interesting dichotomy: the problem is $\mathsf{PSPACE}$-complete when $d = 2$ and $k$ is large but can be solved efficiently when $d \geq 3$ and $k \geq d+1$. For chordal graphs, we show that the problem is $\mathsf{PSPACE}$-complete for even values of $d \geq 2$. Finally, we design a quadratic-time algorithm to solve the problem on paths for any $d \geq 2$ and $k \geq d+1$.
---

Title: Independent Set Reconfiguration Under Bounded-Hop Token
Link: https://arxiv.org/abs/2407.11768
Tags: arxiv, csds
Abstract/Content: arXiv:2407.11768v2 Announce Type: replace Abstract: The independent set reconfiguration problem (ISReconf) is the problem of determining, for given independent sets I_s and I_t of a graph G, whether I_s can be transformed into I_t by repeatedly applying a prescribed reconfiguration rule that transforms an independent set to another. As reconfiguration rules for the ISReconf, the Token Sliding (TS) model and the Token Jumping (TJ) model are commonly considered. While the TJ model admits the addition of any vertex (as far as the addition yields an independent set), the TS model admits the addition of only a neighbor of the removed vertex. It is known that the complexity status of the ISReconf differs between the TS and TJ models for some graph classes. In this paper, we analyze how changes in reconfiguration rules affect the computational complexity of reconfiguration problems. To this end, we generalize the TS and TJ models to a unified reconfiguration rule, called the k-Jump model, which admits the addition of a vertex within distance k from the removed vertex. Then, the TS and TJ models are the 1-Jump and D(G)-Jump models, respectively, where D(G) denotes the diameter of a connected graph G. We give the following three results: First, we show that the computational complexity of the ISReconf under the k-Jump model for general graphs is equivalent for all k >= 3. Second, we present a polynomial-time algorithm to solve the ISReconf under the 2-Jump model for split graphs. We note that the ISReconf under the 1-Jump (i.e., TS) model is PSPACE-complete for split graphs, and hence the complexity status of the ISReconf differs between k = 1 and k = 2. Third, we consider the optimization variant of the ISReconf, which computes the minimum number of steps of any transformation between Is and It. We prove that this optimization variant under the k-Jump model is NP-complete for chordal graphs of diameter at most 2k + 1, for any k >=3.
---

Title: Redundancy Is All You Need (for CSP Sparsification)
Link: https://arxiv.org/abs/2411.03451
Tags: arxiv, csds
Abstract/Content: arXiv:2411.03451v2 Announce Type: replace Abstract: The seminal work of Bencz\'ur and Karger demonstrated cut sparsifiers of near-linear size. Subsequent extensions have yielded sparsifiers for hypergraph cuts and more recently linear codes over Abelian groups. A decade ago, Kogan and Krauthgamer asked about the sparsifiability of arbitrary constraint satisfaction problems (CSPs). For this question, a trivial lower bound is the size of a non-redundant CSP instance, which admits, for each constraint, an assignment satisfying only that constraint (so that no constraint can be dropped by the sparsifier). For instance, for graph cuts, spanning trees are non-redundant instances. Our main result is that redundant clauses are sufficient for sparsification: for any CSP predicate R, every unweighted instance of CSP(R) has a sparsifier of size at most its non-redundancy (up to polylog and $1/\epsilon$ factors). For weighted instances, we similarly pin down the sparsifiability to the so-called chain length of the predicate. These results precisely determine the extent to which any CSP can be sparsified. Our result is established in the general setting of non-linear codes, or equivalently set families, yielding a VC-type theorem for multiplicative error approximation. A key technical ingredient in our work is a novel application of the entropy method from Gilmer's recent breakthrough on the union-closed sets conjecture. As an immediate consequence of our main theorem, a number of results in the non-redundancy literature immediately extend to CSP sparsification. We also contribute new techniques for understanding the non-redundancy of CSP predicates. By adapting methods from the matching vector codes literature in coding theory, we are able to construct an explicit predicate whose non-redundancy lies between $\Omega(n^{1.5})$ and $\widetilde{O}(n^{1.6})$, the first example with a provably non-integral exponent.
---

Title: Sparse induced subgraphs in $P_7$-free graphs of bounded clique number
Link: https://arxiv.org/abs/2412.14836
Tags: arxiv, csds
Abstract/Content: arXiv:2412.14836v4 Announce Type: replace Abstract: Many natural computational problems, including e.g. Max Weight Independent Set, Feedback Vertex Set, or Vertex Planarization, can be unified under an umbrella of finding the largest sparse induced subgraph, that satisfies some property definable in CMSO$_2$ logic. It is believed that each problem expressible with this formalism can be solved in polynomial time in graphs that exclude a fixed path as an induced subgraph. This belief is supported by the existence of a quasipolynomial-time algorithm by Gartland, Lokshtanov, Pilipczuk, Pilipczuk, and Rz\k{a}\.zewski [STOC 2021], and a recent polynomial-time algorithm for $P_6$-free graphs by Chudnovsky, McCarty, Pilipczuk, Pilipczuk, and Rz\k{a}\.zewski [SODA 2024]. In this work we extend polynomial-time tractability of all such problems to $P_7$-free graphs of bounded clique number.
---

Title: Estimating Random-Walk Probabilities in Directed Graphs
Link: https://arxiv.org/abs/2504.16481
Tags: arxiv, csds
Abstract/Content: arXiv:2504.16481v4 Announce Type: replace Abstract: We study discounted random walks in directed graphs. In each step, the walk either terminates with a constant probability $\alpha$, or proceeds to a random out-neighbor. Our goal is to estimate the probability $\pi(s, t)$ that a discounted random walk starting from $s$ terminates at $t$. This probability is also known as the Personalized PageRank (PPR) score, which measures the relevance of $t$ to $s$, for instance, when $s$ and $t$ are web pages on the Internet. We aim to estimate $\pi(s, t)$ within a constant relative error with constant probability. A variety of algorithms have been developed for several problem variants, such as single-pair, single-source, single-target, and single-node estimation, under both worst-case and average-case settings, and for different combinations of allowed graph queries. However, in many important cases, there remain polynomial gaps between known upper and lower bounds. In this paper, we establish tight upper and lower bounds (up to logarithmic factors of $n$) for all problem variants and query combinations, closing all existing gaps in both the worst-case and average-case settings. Below we give some examples for the worst-case settings. As an upper-bound example, the classic power method estimates $\pi(s,t)$ if it is above a threshold $\delta$ in time $O(m\log(1/\delta))$ but $\pi(s,t)$ can be as small as $1/n^{\Theta(n)}$. For contrast, we propose algorithms that deterministically estimate arbitrarily small $\pi(s,t)$ in $O(m\log n)$ time. As a lower-bound example, we improve the lower bound for the single-pair problem from $\Omega(\min\{n,1/\delta\})$ to $\Omega(\min\{m,1/\delta\})$, which is optimal (up to logarithmic factors) since a simple Monte Carlo estimate takes $O(1/\delta)$ time.
---

Title: Treewidth Parameterized by Feedback Vertex Number
Link: https://arxiv.org/abs/2504.18302
Tags: arxiv, csds
Abstract/Content: arXiv:2504.18302v3 Announce Type: replace Abstract: We provide the first algorithm for computing an optimal tree decomposition for a given graph $G$ that runs in single exponential time in the feedback vertex number of $G$, that is, in time $2^{O(\text{fvn}(G))}\cdot n^{O(1)}$, where $\text{fvn}(G)$ is the feedback vertex number of $G$ and $n$ is the number of vertices of $G$. On a classification level, this improves the previously known results by Chapelle et al. [Discrete Applied Mathematics '17] and Fomin et al. [Algorithmica '18], who independently showed that an optimal tree decomposition can be computed in single exponential time in the vertex cover number of $G$. One of the biggest open problems in the area of parameterized complexity is whether we can compute an optimal tree decomposition in single exponential time in the treewidth of the input graph. The currently best known algorithm by Korhonen and Lokshtanov [STOC '23] runs in $2^{O(\text{tw}(G)^2)}\cdot n^4$ time, where $\text{tw}(G)$ is the treewidth of $G$. Our algorithm improves upon this result on graphs $G$ where $\text{fvn}(G)\in o(\text{tw}(G)^2)$. On a different note, since $\text{fvn}(G)$ is an upper bound on $\text{tw}(G)$, our algorithm can also be seen either as an important step towards a positive resolution of the above-mentioned open problem, or, if its answer is negative, then a mark of the tractability border of single exponential time algorithms for the computation of treewidth.
---

Title: Truthful Calibration Errors for Multi-Class Prediction
Link: https://arxiv.org/abs/2510.06388
Tags: arxiv, csds
Abstract/Content: arXiv:2510.06388v2 Announce Type: replace-cross Abstract: Calibrated predictions are useful because their numerical values can be interpreted as probabilities. Calibration errors are therefore widely used to evaluate, compare, and tune probabilistic predictors. Recently, Haghtalab et al. (2024) introduced an additional requirement for such measures: truthfulness. A calibration measure is truthful if a predictor minimizes its expected measured error by reporting the true conditional label distribution. Many standard empirical calibration errors are non-truthful: a predictor may appear better calibrated by distorting its probabilities rather than reporting them truthfully. We study the practical role of truthfulness for calibration measurement in multiclass prediction. First, we introduce perfectly truthful calibration errors for multidimensional linear properties of the label distribution, generalizing the truthful calibration error for binary predictions in Hartline et al. (2025). This framework includes full multiclass calibration and classwise calibration. We also identify a truthful correction for confidence calibration. Second, we characterize the decision-theoretic implications of these truthful errors. For calibrated predictors, truthful calibration errors preserve the Blackwell dominance: a more informative calibrated predictor receives no larger expected error. Third, we show that this decision-theoretic interpretation explains and mitigates the well-observed ranking robustness problem of binned calibration errors. Empirically, non-truthful confidence-based errors can reverse model rankings when the number of bins changes, while our truthful errors give more stable rankings across binning choices.
---

Title: PLS-complete problems with lexicographic cost functions: Max-$k$-SAT and Abelian Permutation Orbit Minimization
Link: https://arxiv.org/abs/2510.15712
Tags: arxiv, csds
Abstract/Content: arXiv:2510.15712v3 Announce Type: replace-cross Abstract: How hard is it to find a local optimum? If we are given a graph and want to find a locally maximal cut--meaning that the number of edges in the cut can't be improved by moving a single vertex from one side to the other--then just iterating improving steps finds a local maximum in $ |E|$ steps. If, on the other hand, the edges are weighted, this problem becomes hard for the class PLS (Polynomial Local Search). We are interested in optimization problems with lexicographic costs. For Max-Cut this would mean that the edges $e_1,\dots, e_m$ have costs $c(e_i) = 2^i$. For such a cost function finding a global Max-Cut is easy. In contrast, we show that it is PLS-complete to find an assignment for a 4-CNF formula that is locally maximal (when the clauses have lexicographic weights); and also for a 3-CNF when we allow switching two variables at a time. We use these results to answer a question in Scheder and Tantow, who showed that finding a lexicographic local minimum of a string $s \in \{0,1\}^n$ under the action of a list of given permutations $\pi_1, \dots, \pi_k \in S_{n}$ is PLS-complete. They ask whether the problem stays PLS-complete when the $\pi_1,\dots,\pi_k$ commute, i.e., generate an Abelian subgroup $G$ of $S_n$. We show that it does, and in fact stays PLS-complete even (1) when every element in $G$ has order two or (2) when $G$ is cyclic. Additionally, we use it to further investigate the complexity of computing pure $\alpha$-Nash equilibria in congestion games. Using lexicographic 4-SAT, we obtain a simple proof of the PLS-completeness originally shown by Skopalik and V\"ocking that can be extended to exponential and polynomial delay functions with positive coefficients. The number of strategies per player and players per resource is bounded. However, the degree of the polynomials is not bounded by a constant.
---

Title: A Tight Double-Exponentially Lower Bound for High-Multiplicity Bin Packing
Link: https://arxiv.org/abs/2512.02691
Tags: arxiv, csds
Abstract/Content: arXiv:2512.02691v3 Announce Type: replace-cross Abstract: Consider a high-multiplicity Bin Packing instance $I$ with $d$ distinct item types. In 2014, Goemans and Rothvoss gave an algorithm with runtime ${{|I|}^2}^{O(d)}$ for this problem~[SODA'14], where $|I|$ denotes the encoding length of the instance $I$. Although Jansen and Klein~[SODA'17] later developed an algorithm that improves upon this runtime in a special case, it has remained a major open problem by Goemans and Rothvoss~[J.ACM'20] whether the doubly exponential dependency on $d$ is necessary. We solve this open problem by showing that unless the ETH fails, there is no algorithm solving the high-multiplicity Bin Packing problem in time ${{|I|}^2}^{o(d)}$. To prove this, we introduce a novel reduction from 3-SAT. The core of our construction is efficiently encoding all information from a 3-SAT instance with $n$ variables into an ILP with $O(\log(n))$ variables and constraints. This result confirms that the Goemans and Rothvoss algorithm is essentially best-possible for Bin Packing parameterized by the number $d$ of item sizes in the context of XP time algorithms.
---

Title: Cost-aware Duration Prediction for Software Upgrades in Datacenters
Link: https://arxiv.org/abs/2212.05155
Tags: arxiv, csdc
Abstract/Content: arXiv:2212.05155v2 Announce Type: replace Abstract: Software upgrades are critical to maintaining server reliability in datacenters. While job duration prediction and scheduling have been extensively studied, the unique challenges posed by software upgrades remain largely under-explored. This paper presents the first in-depth investigation into software upgrade scheduling at datacenter scale. We begin by characterizing various types of upgrades and then frame the scheduling task as a constrained optimization problem. To address this problem, we introduce Acela, a cost-aware duration prediction framework designed to improve upgrade scheduling efficiency and throughput while meeting service-level objectives (SLOs). Acela accounts for asymmetric misprediction costs, strategically selects the best predictive models, and mitigates straggler-induced overestimations. Evaluations on Meta's production datacenter systems demonstrate that Acela significantly increases efficiency of the existing upgrade scheduler by improving upgrade window utilization by 1.25X, increasing the number of scheduled and completed upgrades by 33% and 41%, and reducing cancellation rates by 2.4X. The code and data sets will be released after paper acceptance.
---

Title: VMT19937: A SIMD-Friendly Pseudo Random Number Generator based on Mersenne Twister 19937
Link: https://arxiv.org/abs/2309.16682
Tags: arxiv, csds
Abstract/Content: arXiv:2309.16682v2 Announce Type: replace Abstract: Many simulation applications require the generation of long sequences of pseudo-random numbers. Linear recurrences modulo 2 are commonly used as the fundamental building block for constructing pseudo-random number generators with extended periods and excellent statistical properties. These generators consist of a lengthy binary state vector that evolves iteratively through linear transformations. One widely accepted pseudo-random generator in this category is the Mersenne twister 19937 (MT19937), proposed by Matsumoto and Nishimura, which has been implemented in numerous software libraries and numerical packages. The MT19937's popularity stems from its favorable distribution properties and the simplicity and speed of its algorithm. The linear transformation responsible for evolving the binary state vector can be expressed as a concise set of elementary bit manipulations. However, this transformation does not fully utilize the potential for parallelization through SIMD instructions available on modern hardware, limiting further speed enhancements. This paper introduces a new SIMD-friendly random number generator, which maintains the same statistical properties and period as the MT19937. It combines the random streams of multiple MT19937 instances with state vectors de-phased via jump-ahead transformations, then polls each instance in a round-robin fashion. By evolving their vector states simultaneously, the new generator achieves perfect vectorization, fully leveraging on SIMD hardware capabilities. Comprehensive test results demonstrate that the throughput of the new generator scales approximately linearly with the width of the SIMD registers used. This provides significant speed improvements, especially on modern CPUs equipped with larger SIMD registers, and allows for efficient generation of random numbers for various simulation applications.
---

Title: CHIRON: Accelerating Node Synchronization without Security Trade-offs in Distributed Ledgers
Link: https://arxiv.org/abs/2401.14278
Tags: arxiv, csdc
Abstract/Content: arXiv:2401.14278v3 Announce Type: replace Abstract: Blockchain performance has historically faced challenges posed by the throughput limitations of consensus algorithms. Recent breakthroughs in research have successfully alleviated these constraints by introducing a modular architecture that decouples consensus from execution. The move toward independent optimization of the consensus layer has shifted attention to the execution layer. While concurrent transaction execution is a promising solution for increasing throughput, practical challenges persist. Its effectiveness varies based on the workloads, and the associated increased hardware requirements raise concerns about undesirable centralization. This increased requirement results in full nodes and stragglers synchronizing from signed checkpoints, decreasing the trustless nature of blockchain systems. In response to these challenges, this paper introduces Chiron, a system designed to extract execution hints for the acceleration of straggling and full nodes. Notably, Chiron achieves this without compromising the security of the system or introducing overhead on the critical path of consensus. Evaluation results demonstrate a notable speedup of up to 30%, effectively addressing the gap between theoretical research and practical deployment. The quantification of this speedup is achieved through realistic blockchain benchmarks derived from a comprehensive analysis of Ethereum and Solana workloads, constituting an independent contribution.
---

Title: EnFed: An Energy-aware Federated Learning in Resource Constrained Environments for Human Activity Recognition
Link: https://arxiv.org/abs/2412.00768
Tags: arxiv, csdc
Abstract/Content: arXiv:2412.00768v2 Announce Type: replace Abstract: The human activity recognition (HAR) and recommendation applications for mobile users require a privacy-aware and accurate data analysis model with lower time and lower energy consumption. The use of federated learning (FL) to develop a privacy-aware HAR model is an emerging research topic. However, the participating mobile devices in the FL process may slow down due to their limited computational resources, connectivity interruption, and limited battery life. To address these challenges, this paper proposes an energy-efficient FL method referred to as EnFed, with a case study on HAR. In EnFed, a mobile device that needs a model for an application requests its nearby devices with respect to an incentive. The nearby devices, which agree to the offered incentive, send their local model updates, i.e., updated local model parameters for that application, to the requesting device. The device, after receiving local model updates from the contributors, aggregates them to build a global model and then fits the model to its own dataset to build its own local model. The results show that using EnFed a resource-limited device obtains an accurate prediction model at lower time and lower energy consumption. The experimental results show that EnFed achieves above 95% prediction accuracy and outperforms the baselines. EnFed also reduces the response time above 90% than the cloud-only framework. The comparative study shows that EnFed outperforms the existing HAR approaches.
---

Title: Experimentally validated quantum-secure federated learning over a multi-user quantum network
Link: https://arxiv.org/abs/2501.12709
Tags: arxiv, csdc
Abstract/Content: arXiv:2501.12709v2 Announce Type: replace-cross Abstract: Federated learning enables decentralized, privacy-preserving training but remains vulnerable to privacy leakage in the quantum era. Quantum federated learning (QFL) offers a promising path towards enhanced security and efficiency. However, a practical and experimentally validated QFL protocol utilizing near-term quantum techniques to address data privacy has been lacking. Here we present QuNetQFL, a QFL protocol implemented on quantum networks, in which local model updates are masked with distributed quantum secret keys, offering information-theoretic security during aggregation. We experimentally validate the protocol on a four-client quantum network and benchmark its performance using the generated keys on quantum and real-world datasets. Adding a single quantum client significantly improves global accuracy for classifying multipartite entangled and non-stabilizer quantum datasets. For language tasks, we apply QuNetQFL to sentiment analysis by federated fine-tuning of a hybrid classical-quantum language model, achieving comparable and robust performance in simulation and on real quantum hardware. Large-scale simulations further demonstrate scalability to 200 clients for handwritten-digit recognition, with rapid convergence and a $75\%$ reduction in communication cost via model compression. Our work establishes a practical and scalable route to quantum-secure federated learning for the emerging quantum internet.
---

Title: Responsible Federated LLMs via Safety Filtering and Constitutional AI
Link: https://arxiv.org/abs/2502.16691
Tags: arxiv, csdc
Abstract/Content: arXiv:2502.16691v2 Announce Type: replace-cross Abstract: Recent research has increasingly focused on training large language models (LLMs) using federated learning, known as FedLLM. However, responsible AI (RAI), which aims to ensure safe and trustworthy responses, remains underexplored in this context. In FedLLM, client-side training data may contain harmful content, resulting in unsafe LLMs that can generate inappropriate responses. Aggregating such models into a global model and redistributing it to clients risks the widespread deployment of unsafe LLMs. To address this, we incorporate two well-established RAI techniques into FedLLM: safety filtering and constitutional AI. Our experiments show that these methods significantly improve LLM safety, achieving over 20% improvement on AdvBench.
---

Title: TeleRAG: Efficient Retrieval-Augmented Generation Inference with Lookahead Retrieval
Link: https://arxiv.org/abs/2502.20969
Tags: arxiv, csdc
Abstract/Content: arXiv:2502.20969v4 Announce Type: replace Abstract: Retrieval-augmented generation (RAG) extends large language models (LLMs) with external data sources to enhance factual correctness and domain coverage. Modern RAG pipelines rely on large datastores, creating a significant system challenge: achieving high throughput and low latency is difficult, especially when GPU memory is limited. To address these challenges, we propose TeleRAG, an efficient inference system that reduces latency and improves throughput with minimal GPU memory requirements. The core innovation of TeleRAG is lookahead retrieval, a prefetching mechanism that predicts required data and transfers them from CPU to GPU in parallel with LLM generation. In addition, TeleRAG adopts a prefetching scheduler and a cache-aware scheduler to support efficient multi-GPU inference with minimal overhead. Evaluations show TeleRAG achieves up to a 1.53x average end-to-end latency reduction (single-query) and 1.83x higher average throughput (batched), as well as good scalability in throughput. This confirms the practical utility of TeleRAG for faster and more memory-efficient deployments of RAG applications.
---

Title: CoBRA: A Universal Strategyproof Confirmation Protocol for Quorum-based Proof-of-Stake Blockchains
Link: https://arxiv.org/abs/2503.16783
Tags: arxiv, csdc
Abstract/Content: arXiv:2503.16783v4 Announce Type: replace-cross Abstract: The security of many Proof-of-Stake (PoS) payment systems relies on quorum-based State Machine Replication (SMR) protocols. While classical analyses assume purely Byzantine faults, real-world systems must tolerate both arbitrary failures and strategic, profit-driven validators. We therefore study quorum-based SMR under a hybrid model with honest, Byzantine, and rational participants. We first establish the fundamental limitations of traditional consensus mechanisms, proving two impossibility results: (1) in partially synchronous networks, no quorum-based protocol can achieve SMR when rational and Byzantine validators collectively exceed $1/3$ of the participants; and (2) even under synchronous network assumptions, SMR remains unattainable if this coalition comprises more than $2/3$ of the validator set. Assuming a synchrony bound $\Delta$, we show how to extend any quorum-based SMR protocol to tolerate up to $1/3$ Byzantine and $1/3$ rational validators by modifying only its finalization rule. Our approach enforces a necessary bound on the total transaction volume finalized within any time window $\Delta$ and introduces the \emph{strongest chain rule}, which enables efficient finalization of transactions when a supermajority of honest participants provably supports execution. Empirical analysis of Ethereum and Cosmos demonstrates validator participation exceeding the required $5/6$ threshold in over $99%$ of blocks, supporting the practicality of our design. Finally, we present a recovery mechanism that restores safety and liveness after consistency violations, even with up to $5/9$ Byzantine stake and $1/9$ rational stake, guaranteeing full reimbursement of provable client losses.
---

Title: Snow: Self-organizing Broadcast Protocol for Cloud
Link: https://arxiv.org/abs/2504.02676
Tags: arxiv, csdc
Abstract/Content: arXiv:2504.02676v2 Announce Type: replace Abstract: In large-scale distributed applications, efficient and reliable broadcast protocols are essential for node communication. Tree-based broadcast lacks flexibility and may suffer performance degradation or even broadcast failure when cluster membership changes. Gossip-based broadcast incurs high bandwidth overhead and only provides probabilistic delivery guarantees. In tree-based broadcasting, when an internal node leaves, its child nodes need to reconnect to a new parent. This process may introduce instability, leading to potential message duplication and increased transmission latency. However, in cloud environments, node departures and arrivals are common, causing frequent performance degradation in tree-based broadcasting. This paper introduces Snow, a self-organizing broadcast protocol designed for cloud environments. Instead, it dynamically sends or forwards messages based on each node's membership view, ultimately forming a broadcast structure resembling a multi-way balanced tree(the height difference of leaf nodes is at most 1). Our experimental results showed that Snow maintains message delivery reliability and latency guarantees under node churn while maintaining low overhead without sending unnecessary redundant messages.
---

Title: CarbonScaling: Extending Neural Scaling Laws for Carbon Footprint in Large Language Models
Link: https://arxiv.org/abs/2508.06524
Tags: arxiv, csdc
Abstract/Content: arXiv:2508.06524v2 Announce Type: replace-cross Abstract: Large language models (LLMs) increasingly follow neural scaling laws that tie performance gains to rapidly expanding computational budgets, raising concerns about the sustainability of frontier-scale training. Existing carbon-estimation methods largely depend on regression over historical runs and fail to capture critical system-level factors, including hardware heterogeneity, distributed parallelism, communication overhead, and architectural sparsity. We present \textit{CarbonScaling}, a hardware-aware analytical framework for modeling the carbon scaling behavior of frontier LLM training. The framework integrates neural scaling laws, distributed training strategies, accelerator and interconnect modeling, and operational and embodied carbon accounting to estimate feasible hardware configurations and associated emissions. CarbonScaling jointly models tensor, pipeline, data, and expert parallelism while incorporating memory, bandwidth, utilization, and runtime constraints. Experimental validation demonstrates substantially higher fidelity than regression-based baselines and highlights the growing importance of embodied carbon at trillion-parameter scales. Source code: \url{https://github.com/UnchartedRLab/CarbonScaling}.
---

Title: A Machine With Human-Like Memory Systems
Link: https://arxiv.org/abs/2204.01611
Tags: arxiv, csai
Abstract/Content: arXiv:2204.01611v3 Announce Type: replace Abstract: Inspired by the cognitive science theory, we explicitly model an agent with both semantic and episodic memory systems, and show that it is better than having just one of the two memory systems. In order to show this, we have designed and released our own challenging environment, "the Room", compatible with OpenAI Gym, where an agent has to properly learn how to encode, store, and retrieve memories to maximize its rewards. The Room environment allows for a hybrid intelligence setup where machines and humans can collaborate. We show that two agents collaborating with each other results in better performance than one agent acting alone.
---

Title: A Machine with Short-Term, Episodic, and Semantic Memory Systems
Link: https://arxiv.org/abs/2212.02098
Tags: arxiv, csai
Abstract/Content: arXiv:2212.02098v5 Announce Type: replace Abstract: Inspired by the cognitive science theory of the explicit human memory systems, we have modeled an agent with short-term, episodic, and semantic memory systems, each of which is modeled with a knowledge graph. To evaluate this system and analyze the behavior of this agent, we designed and released our own reinforcement learning agent environment, "the Room", where an agent has to learn how to encode, store, and retrieve memories to maximize its return by answering questions. We show that our deep Q-learning based agent successfully learns whether a short-term memory should be forgotten, or rather be stored in the episodic or semantic memory systems. Our experiments indicate that an agent with human-like memory systems can outperform an agent without this memory structure in the environment.
---

Title: Revisiting Long-term Time Series Forecasting: An Investigation on Linear Mapping
Link: https://arxiv.org/abs/2305.10721
Tags: arxiv, csai
Abstract/Content: arXiv:2305.10721v2 Announce Type: replace-cross Abstract: Introduction: Long-term time series forecasting (LTSF) has gained significant attention in recent years. While various specialized designs exist for capturing temporal dependency, recent studies have shown that even a single linear layer can achieve competitive performance. This paper investigates the intrinsic effectiveness of recent LTSF approaches and reveals the critical role of affine mapping. Materials and methods: We conduct comprehensive experiments on both simulated and real-world datasets to analyze the components of state-of-the-art models. A theoretical analysis is provided to explain the working mechanisms of affine mapping in periodic signal forecasting. We evaluate the impact of reversible normalization and input horizon extension on model robustness. Results: We find that (1) affine mapping dominates forecasting performance across commonly utilized benchmarks, with models learning similar transition matrices from input to output; (2) affine mapping effectively captures periodic patterns but struggles with non-periodic signals or time series with varying periods across channels; (3) reversible normalization significantly enhances trend forecasting by transforming non-periodic trends into periodic-like patterns; (4) increasing input horizon improves performance on multi-channel data with different periods. Code is available at: \url{https://github.com/plumprc/RTSF}. Conclusions: Our findings provide theoretical and experimental insights into the working mechanisms of LTSF models, highlighting both the strengths and limitations of linear approaches. The results suggest that future model development should focus on handling cross-channel period variations and non-periodic components.
---

Title: Universal Time-Series Representation Learning: A Survey
Link: https://arxiv.org/abs/2401.03717
Tags: arxiv, csai
Abstract/Content: arXiv:2401.03717v4 Announce Type: replace-cross Abstract: Time-series data exists in every corner of real-world systems and services, ranging from satellites in the sky to wearable devices on human bodies. Learning representations by extracting and inferring valuable information from these time series is crucial for understanding the complex dynamics of particular phenomena and enabling informed decisions. With the learned representations, we can perform numerous downstream analyses more effectively. Among several approaches, deep learning has demonstrated remarkable performance in extracting hidden patterns and features from time-series data without manual feature engineering. This survey first presents a novel taxonomy based on three fundamental elements in designing state-of-the-art universal representation learning methods for time series. According to the proposed taxonomy, we comprehensively review existing studies and discuss their intuitions and insights into how these methods enhance the quality of learned representations. Finally, as a guideline for future studies, we summarize commonly used experimental setups and datasets and discuss several promising research directions. An up-to-date corresponding resource is available at https://github.com/itouchz/awesome-deep-time-series-representations.
---

Title: Principles of frugal inference and control
Link: https://arxiv.org/abs/2406.14427
Tags: arxiv, csai
Abstract/Content: arXiv:2406.14427v4 Announce Type: replace Abstract: A central challenge for intelligent agents in an uncertain world is striking the right balance between utility maximization and resource use, not only for external movement but also for internal computation. Existing theories of control under uncertainty typically treat inference as cost-free, despite the substantial computational and energetic burden it imposes in both artificial and biological systems. To remedy this problem, we introduce a novel variant of the POMDP framework in which the information acquired through inference is treated as a resource that must be optimized alongside utility. Solving a local linear-Gaussian approximation of the resulting problem reveals three general principles of resource-efficient control. First, when information is costly, inference shifts from a Bayes-optimal (lossless) compression of the past to a lossy regime that strategically leaves some uncertainty unresolved to optimize resource use. Second, relaxing exact Bayesian inference creates a manifold of equivalent solutions, reflecting multiple ways to combine imperfect inference with compensatory control. This flexibility can be used to meet additional objectives or constraints without sacrificing performance on the original task. Third, beyond goal attainment, control can be leveraged to counteract estimation errors and steer the system into regimes where representation costs are lower. We empirically demonstrate that these principles generalize beyond the local linear-Gaussian approximation, enabling the solution of nonlinear control problems such as pole balancing and drone stabilization. Together, these results establish a framework for rational computation that extends existing approaches to information-constrained decision-making and offers normative insight into how brains and machines can achieve effective behavior under tight computational constraints.
---

Title: $\texttt{SynC}$: Synergistic Boosting of Structure and Representation for Deep Graph Clustering
Link: https://arxiv.org/abs/2406.15797
Tags: arxiv, csai
Abstract/Content: arXiv:2406.15797v2 Announce Type: replace-cross Abstract: Employing graph neural networks (GNNs) for graph clustering has shown promising results in deep graph clustering. However, existing methods disregard the reciprocal relationship between representation learning and structure augmentation: the more homogeneous the graph, the more cohesive the node representations; the more cohesive the node representations, the more reliable the structure augmentation becomes. Moreover, the generalization ability of existing GNN-based models on the low homophily graph is relatively poor. To this end, we propose a graph clustering framework named Synergistic Deep Graph Clustering Network (SynC). SynC employs a Transform Input Graph Auto-Encoder (TIGAE) to obtain high-quality embeddings via mitigating the representations collapse issue of GAE for guiding structure augmentation. Then, we re-capture neighborhood representations on the refined graph to obtain clustering-friendly embeddings and conduct self-supervised clustering. Notably, these two stages share weights, resulting in synergistic boosting while significantly reducing the number of model parameters. Additionally, we introduce a structure fine-tuning strategy to improve the model's generalization on the low homophily graph. Extensive experiments on benchmark datasets demonstrate the superiority of SynC. The code is released at GitHub.
---

Title: AASIST3: KAN-Enhanced AASIST Speech Deepfake Detection using SSL Features and Additional Regularization for the ASVspoof 2024 Challenge
Link: https://arxiv.org/abs/2408.17352
Tags: arxiv, csai
Abstract/Content: arXiv:2408.17352v2 Announce Type: replace-cross Abstract: Automatic Speaker Verification (ASV) systems, which identify speakers based on their voice characteristics, have numerous applications, such as user authentication in financial transactions, exclusive access control in smart devices, and forensic fraud detection. However, the advancement of deep learning algorithms has enabled the generation of synthetic audio through Text-to-Speech (TTS) and Voice Conversion (VC) systems, exposing ASV systems to potential vulnerabilities. To counteract this, we propose a novel architecture named AASIST3. By enhancing the existing AASIST framework with Kolmogorov-Arnold networks, additional layers, encoders, and pre-emphasis techniques, AASIST3 achieves a more than twofold improvement in performance. It demonstrates minDCF results of 0.5357 in the closed condition and 0.1414 in the open condition, significantly enhancing the detection of synthetic voices and improving ASV security. \textbf{The new version of the model is publicly available at \href{https://huggingface.co/lab260/Spectra-AASIST3}{\underline{HuggingFace (2026)}}}
---

Title: Language Models as Efficient Reward Function Searchers for Custom-Environment Multi-Objective Reinforcement
Link: https://arxiv.org/abs/2409.02428
Tags: arxiv, csai
Abstract/Content: arXiv:2409.02428v4 Announce Type: replace-cross Abstract: Achieving the effective design and improvement of reward functions in reinforcement learning (RL) tasks with complex custom environments and multiple requirements presents considerable challenges. In this paper, we propose ERFSL, an efficient reward function searcher using LLMs, which enables LLMs to be effective white-box searchers and highlights their advanced semantic understanding capabilities. Specifically, we generate reward components for each numerically explicit user requirement and employ a reward critic to identify the correct code form. Then, LLMs assign weights to the reward components to balance their values and iteratively adjust the weights without ambiguity and redundant adjustments by flexibly adopting directional mutation and crossover strategies, similar to genetic algorithms, based on the context provided by the training log analyzer. We applied the framework to a customized data collection RL task without direct human feedback or reward examples (zero-shot learning). The reward critic successfully corrects the reward code with only one feedback instance for each requirement, effectively preventing unrectifiable errors. The initialization of weights enables the acquisition of different reward functions within the Pareto solution set without the need for weight search. Even in cases where a weight is 500 times off, on average, only 5.2 iterations are needed to meet user requirements. The ERFSL also works well with most prompts utilizing GPT-4o mini, as we decompose the weight searching process to reduce the requirement for numerical and long-context understanding capabilities.
---

Title: Trustworthiness in Retrieval-Augmented Generation Systems: A Survey
Link: https://arxiv.org/abs/2409.10102
Tags: arxiv, csai
Abstract/Content: arXiv:2409.10102v2 Announce Type: replace-cross Abstract: Retrieval-Augmented Generation (RAG) has quickly grown into a pivotal paradigm in the development of Large Language Models (LLMs). Although existing research mainly emphasizes accuracy and efficiency, the trustworthiness of RAG systems remains insufficiently explored. RAG can improve LLM reliability by grounding responses in external and up-to-date knowledge, reducing hallucinations. However, unreliable retrieval or improper knowledge utilization may still lead to undesirable outputs. To address these concerns, we propose a unified framework, Trust-RAG Compass, that assesses the trustworthiness of RAG systems across six key dimensions: factuality, robustness, fairness, transparency, accountability, and privacy. Within this framework, we provide a thorough review of the existing literature along each dimension. Furthermore, we introduce an evaluation benchmark, TRC Bench (\underline{T}rust-\underline{R}AG \underline{C}ompass \underline{Bench}mark), regarding the six dimensions and conduct comprehensive evaluations for a variety of proprietary and open-source models. Our results shed light on the performance gaps between different types of LLMs across varying dimensions of trustworthiness. Finally, we identify key challenges and promising directions for future research based on our findings. Through this work, we aim to provide a structured foundation for subsequent investigations and practical guidance for developing trustworthy RAG systems in real-world scenarios.
---

Title: Leveraging Unsupervised Learning for Cost-Effective Visual Anomaly Detection
Link: https://arxiv.org/abs/2409.15980
Tags: arxiv, csai
Abstract/Content: arXiv:2409.15980v2 Announce Type: replace-cross Abstract: Traditional machine learning-based visual inspection systems require extensive data collection and repetitive model training to improve accuracy. These systems typically require expensive camera, computing equipment and significant machine learning expertise, which can substantially burden small and medium-sized enterprises. This study explores leveraging unsupervised learning methods with pre-trained models and low-cost hardware to create a cost-effective visual anomaly detection system. The research aims to develop a low-cost visual anomaly detection solution that uses minimal data for model training while maintaining generalizability and scalability. The system utilises unsupervised learning models from Anomalib and is deployed on affordable Raspberry Pi hardware through openVINO. The results show that this cost-effective system can complete anomaly defection training and inference on a Raspberry Pi in just 90 seconds using only 10 normal product images, achieving an F1 macro score exceeding 0.95. While the system is slightly sensitive to environmental changes like lighting, product positioning, or background, it remains a swift and economical method for factory automation inspection for small and medium-sized manufacturers. The code is available at https://github.com/Yunbo-max/Cost-Effective-Visual-Anomaly-Detection-using-Unsupervised-Learning.
---


** Raw LLM Output
* cs.DB (Databases)
** 🧐 Обзор
Векторный поиск и обслуживание составных AI-моделей становятся ключевыми темами, с акцентом на дисковые индексы и планировщики, учитывающие SLO. Также наблюдается рост работ по оптимизации хранилищ для блокчейнов и динамическим графам. Исследования направлены на снижение затрат памяти и ускорение планирования запросов в гетерогенных средах.

** 🛠 Практика и Системы
- [[https://arxiv.org/abs/2504.16397][Compass: SLO-aware Query Planner for Compound AI Serving at Scale]]
:WHAT: Планировщик запросов, оптимизирующий размещение операторов составных AI-моделей с учетом SLO по задержке и стоимости.
:IMPACT: Увеличивает_goodput_сервиса в 2.4--5.1 раза и снижает затраты на развертывание в 3.8--4.5 раза.
- [[https://arxiv.org/abs/2505.17152][LSM-VEC: A Large-Scale Disk-Based System for Dynamic Vector Search]]
:WHAT: Дисковая система векторного поиска, интегрирующая иерархические графы с LSM-деревьями для поддержки динамических обновлений.
:IMPACT: Снижает占用ление памяти на 66.2% и превосходит существующие ANN-системы на масштабах в миллиарды векторов.
- [[https://arxiv.org/abs/2604.06579][SonicDB S6: A Storage-Efficient Verkle Trie for High-Throughput Blockchains]]
:WHAT: База данных на основе Verkle Trie для блокчейна Sonic, использующая специализацию узлов и дельта-кодирование.
:IMPACT: Уменьшает живое хранилище на 97.8% и увеличивает пропускную способность в 3.2 раза по сравнению с baseline.
- [[https://arxiv.org/abs/2605.08601][Elastic Scheduling of Intermittent Query Processing in a Cluster Environment]]
:WHAT: Схемы планирования пакетной обработки потоков данных в эластичной кластерной среде с масштабированием узлов.
:IMPACT: Значительно снижает затраты при соблюдении дедлайнов по сравнению с фиксированными конфигурациями узлов.

** 🕸 Графы и Алгоритмы
- [[https://arxiv.org/abs/2605.02171][QuIVer: Rethinking ANN Graph Topology via Training-Free Binary Quantization]]
:ALGO: Индекс ANN, строящий топологию графа непосредственно в пространстве бинарного квантования (2-bit).
:IMPACT: Определяет границы применимости сжатия для векторного поиска, обеспечивая до 5.5x выше пропускную способность на совместимых данных.
- [[https://arxiv.org/abs/2605.16948][Revisiting the Maximum Defective Clique Problem: Faster Branching and a Tighter Upper Bound]]
:ALGO: Фреймворк BBRes с стратегией раннего завершения и новым верхним ограничением на основе раскраски графа.
:IMPACT: Достигает ускорения минимум в 2 раза по сравнению с лучшими точными алгоритмами поиска кликов.
- [[https://arxiv.org/abs/2605.17524][Coordinate Heterogeneity Governs Binary Quantization: From InfoNCE to Recall]]
:ALGO: Аналитическая框架рамка, связывающая неоднородность координат эмбеддингов с эффективностью бинарного квантования.
:IMPACT: Предоставляет принципиальное руководство по дизайну систем квантования для различных типов моделей.

** 📄 Остальное
- [[https://arxiv.org/abs/2507.18406][Factual Inconsistencies in Multilingual Wikipedia Tables]] — Исследование фактических несоответствий в табличных данных многоязычной Википедии.
- [[https://arxiv.org/abs/2605.16365][Machine Learning-Based Pre-Test Risk Stratification for PCR-Confirmed Chlamydia]] — Применение ML для стратификации риска инфекций на основе данных пациентов.
- [[https://arxiv.org/abs/2605.17657][General Science Ranking (GSR): An Open-Source, Citation-Normalized Journal and Conference Classification System]] — Открытая система ранжирования научных журналов и конференций на основе библиометрии.

* cs.DC (Distributed Computing)
** 🧐 Обзор
Исследования сосредоточены на эффективности федеративного обучения, безопасности блокчейн-синхронизации и оптимизации инференса больших языковых моделей. Важным трендом является учет углеродного следа и управление ресурсами в дата-центрах. Протоколы консенсуса адаптируются к смешанным моделям отказов и рационального поведения валидаторов.

** 🛠 Практика и Системы
- [[https://arxiv.org/abs/2212.05155][Cost-aware Duration Prediction for Software Upgrades in Datacenters]]
:WHAT: Фреймворк Acela для прогнозирования длительности обновлений ПО с учетом асимметричных ошибок и затрат.
:IMPACT: Увеличивает утилизацию окон обновлений на 25% и снижает частоту отмен в 2.4 раза в продакшене.
- [[https://arxiv.org/abs/2401.14278][CHIRON: Accelerating Node Synchronization without Security Trade-offs in Distributed Ledgers]]
:WHAT: Система извлечения подсказок выполнения для ускорения синхронизации отстающих узлов в блокчейне.
:IMPACT: Ускоряет синхронизацию на 30% без компромиссов в безопасности или консенсусе.
- [[https://arxiv.org/abs/2502.20969][TeleRAG: Efficient Retrieval-Augmented Generation Inference with Lookahead Retrieval]]
:WHAT: Система инференса RAG с механизмом предвыборки данных (lookahead retrieval) параллельно генерации LLM.
:IMPACT: Снижает задержку на 1.53x и увеличивает пропускную способность в 1.83 раза при ограниченной памяти GPU.
- [[https://arxiv.org/abs/2503.16783][CoBRA: A Universal Strategyproof Confirmation Protocol for Quorum-based Proof-of-Stake Blockchains]]
:WHAT: Протокол подтверждения, устойчивый к смеси византийских и рациональных валидаторов в сетях PoS.
:IMPACT: Гарантирует безопасность и возврат средств при нарушениях консенсуса в реальных условиях Ethereum и Cosmos.
- [[https://arxiv.org/abs/2504.02676][Snow: Self-organizing Broadcast Protocol for Cloud]]
:WHAT: Самоорганизующийся протокол широковещания, формирующий сбалансированную древовидную структуру в облаке.
:IMPACT: Поддерживает надежность доставки и низкую задержку при частых изменениях состава кластера.
- [[https://arxiv.org/abs/2508.06524][CarbonScaling: Extending Neural Scaling Laws for Carbon Footprint in Large Language Models]]
:WHAT: Аналитическая框架рамка для моделирования углеродного следа обучения LLM с учетом аппаратной гетерогенности.
:IMPACT: Позволяет точно оценивать выбросы и выбирать конфигурации оборудования для триллионных моделей.
- [[https://arxiv.org/abs/2412.00768][EnFed: An Energy-aware Federated Learning in Resource Constrained Environments]]
:WHAT: Энергоэффективный метод федеративного обучения для устройств с ограниченными ресурсами.
:IMPACT: Снижает время отклика на 90% и достигает точности выше 95% в задачах распознавания активности.
- [[https://arxiv.org/abs/2501.12709][Experimentally validated quantum-secure federated learning over a multi-user quantum network]]
:WHAT: Протокол квантового федеративного обучения с маскировкой обновлений квантовыми ключами.
:IMPACT: Обеспечивает информационно-теоретическую безопасность и масштабируемость до 200 клиентов.
- [[https://arxiv.org/abs/2502.16691][Responsible Federated LLMs via Safety Filtering and Constitutional AI]]
:WHAT: Интеграция фильтрации безопасности и конституционного AI в федеративное обучение LLM.
:IMPACT: Улучшает безопасность моделей на 20% по benchmarks AdvBench в распределенной среде.

** 📄 Остальное
- (Все статьи категории относятся к системам и протоколам).

* cs.DS (Data Structures & Algorithms)
** 🧐 Обзор
Значительный прогресс в задачах реконфигурации графов и параметризованной сложности, включая новые границы для ширины дерева. Параллельно развиваются методы спарсификации CSP и оценки вероятностей случайных блужданий. Теоретические работы предлагают строгие нижние оценки для задач упаковки и локального поиска.

** 🛠 Практика и Системы
- [[https://arxiv.org/abs/2309.16682][VMT19937: A SIMD-Friendly Pseudo Random Number Generator based on Mersenne Twister 19937]]
:WHAT: Генератор псевдослучайных чисел, оптимизированный для SIMD-инструкций через объединение потоков MT19937.
:IMPACT: Обеспечивает линейное масштабирование пропускной способности с шириной регистров SIMD на современных CPU.

** 🕸 Графы и Алгоритмы
- [[https://arxiv.org/abs/2402.12705][Distance Recoloring]]
:ALGO: Анализ сложности перекрашивания графов с учетом расстояния$d$, доказательство PSPACE-полноты для планарных графов.
:IMPACT: Устанавливает границы вычислительной сложности для задач реконфигурации раскраски.
- [[https://arxiv.org/abs/2407.11768][Independent Set Reconfiguration Under Bounded-Hop Token]]
:ALGO: Обобщение моделей Token Sliding и Jumping, полиномиальный алгоритм для split-графов при k=2.
:IMPACT: Проясняет влияние правил реконфигурации на вычислительную сложность задач на независимые множества.
- [[https://arxiv.org/abs/2411.03451][Redundancy Is All You Need (for CSP Sparsification)]]
:ALGO: Доказательство достаточности избыточных клаузул для спарсификации задач удовлетворения ограничений (CSP).
:IMPACT: Точно определяет степень сжимаемости произвольных CSP предикатов.
- [[https://arxiv.org/abs/2412.14836][Sparse induced subgraphs in $P_7$-free graphs of bounded clique number]]
:ALGO: Полиномиальный алгоритм для поиска разреженных индуцированных подграфов в$P_7$-свободных графах.
:IMPACT: Расширяет класс графов, для которых задачи типа Max Weight Independent Set разрешимы эффективно.
- [[https://arxiv.org/abs/2504.16481][Estimating Random-Walk Probabilities in Directed Graphs]]
:ALGO: Алгоритмы оценки Personalized PageRank с закрытием разрывов между верхними и нижними границами сложности.
:IMPACT: Позволяет детерминированно оценивать малые вероятности за время$O(m\log n)$.
- [[https://arxiv.org/abs/2504.18302][Treewidth Parameterized by Feedback Vertex Number]]
:ALGO: Алгоритм вычисления оптимальной древесной декомпозиции за время$2^{O(\text{fvn})} \cdot n^{O(1)}$.
:IMPACT: Улучшает известные результаты для параметризованной сложности вычисления ширины дерева.

** 📄 Остальное
- [[https://arxiv.org/abs/2306.12282][Online Resource Allocation with Convex-set Machine-Learned Advice]] — Алгоритмы распределения ресурсов с учетом неопределенности ML-советов.
- [[https://arxiv.org/abs/2510.06388][Truthful Calibration Errors for Multi-Class Prediction]] — Введение правдивых метрик ошибки калибровки для многоклассовой классификации.
- [[https://arxiv.org/abs/2510.15712][PLS-complete problems with lexicographic cost functions]] — Исследование сложности локального поиска с лексикографическими функциями затрат.
- [[https://arxiv.org/abs/2512.02691][A Tight Double-Exponentially Lower Bound for High-Multiplicity Bin Packing]] — Доказательство необходимости двойной экспоненты для упаковки контейнеров с высокой кратностью.

* physics.soc-ph (Social Physics & Networks)
** 🧐 Обзор
Внимание смещается к сетям высшего порядка (гиперграфам) и анализу редакторских траекторий в Википедии. Критическому переосмыслению подвергаются законы городского масштабирования и методы оценки научных публикаций. Моделирование коэволюции игр и популяций выявляет новые режимы сотрудничества.

** 🕸 Графы и Алгоритмы
- [[https://arxiv.org/abs/2605.16850][Editorial Trajectories in Wikipedia Reflect Underlying Hyperlink Structure]]
:ALGO: Анализ связи гиперссылок и последовательностей редактирования статей, классификация редакторов.
:IMPACT: Demonstrates that hyperlink structure guides editorial activity, not just reader navigation.
- [[https://arxiv.org/abs/2605.18166][Hypergraphx-data: a repository for higher-order network data]]
:ALGO: Репозиторий данных гиперграфов с поддержкой взвешенных, направленных и временных конфигураций.
:IMPACT: Заполняет пробел в доступности данных для анализа сетей высшего порядка.
- [[https://arxiv.org/abs/2605.18420][The nestedness of higher-order networks]]
:ALGO: Унификация мер вложенности через направленный ациклический граф инкапсуляции.
:IMPACT: Показывает распространенность вложенных структур в социальных системах.
- [[https://arxiv.org/abs/2506.20603][Endogenous Feedback in Coevolutionary Games Reshapes the Stability of Cooperation]]
:ALGO: Модель эндогенной обратной связи, где матрица выплат зависит от уровня сотрудничества.
:IMPACT: Объясняет возникновение стабильного сотрудничества вопреки предсказаниям стандартных игр.

** 📄 Остальное
- [[https://arxiv.org/abs/2510.16046][CARDIO-Affect: A Hamiltonian-Variability Framework for Spatio-Temporal Emotional Pattern Recognition]] — Фреймворк для анализа эмоциональной динамики в социальных группах.
- [[https://arxiv.org/abs/2511.20742][City-level energy and emission assessment based on 20+ million electric vehicle registrations in China]] — Оценка выбросов и энергопотребления электромобилей в городах Китая.
- [[https://arxiv.org/abs/2603.30021][On the Meaning of Urban Scaling]] — Критика интерпретации кросс-секционных законов масштабирования городов.
- [[https://arxiv.org/abs/2604.06223][The Quiet and the Compliant: How Regulation and Polarization Shape Conventional Wisdoms on Corporate Social Engagement]] — Исследование восприятия корпоративной социальной ответственности в рискованных условиях.
- [[https://arxiv.org/abs/2605.14947][From Particles to Policy: Technical Building Blocks for Multi-State SAI Coordination]] — Технические предложения для координации инъекции стратосферных аэрозолей.
- [[https://arxiv.org/abs/2605.17534][The Curious Case of Max Planck retracted papers]] — Анализ причин ретракции исторических статей Макса Планка в цифровых архивах.

* cs.AI (Artificial Intelligence)
** 🧐 Обзор
Развиваются архитектуры агентов с человеческой памятью и эффективные методы детекции аномалий на дешевом оборудовании. В фокусе также надежность RAG-систем и поиск функций вознаграждения с помощью LLM. Линейные модели показывают surprising эффективность в задачах прогнозирования временных рядов.

** 🛠 Практика и Системы
- [[https://arxiv.org/abs/2409.15980][Leveraging Unsupervised Learning for Cost-Effective Visual Anomaly Detection]]
:WHAT: Система детекции визуальных аномалий на Raspberry Pi с использованием необучаемых моделей и предобученных весов.
:IMPACT: Достигает F1 > 0.95 за 90 секунд обучения на 10 изображениях, подходя для малых предприятий.

** 🕸 Графы и Алгоритмы
- [[https://arxiv.org/abs/2406.15797][$\texttt{SynC}$: Synergistic Boosting of Structure and Representation for Deep Graph Clustering]]
:ALGO: Фреймворк кластеризации графов с синергетическим усилением структуры и представлений узлов.
:IMPACT: Улучшает обобщающую способность на графах с низкой гомофилией и снижает количество параметров.

** 📄 Остальное
- [[https://arxiv.org/abs/2204.01611][A Machine With Human-Like Memory Systems]] — Агент с семантической и эпизодической памятью для среды "the Room".
- [[https://arxiv.org/abs/2212.02098][A Machine with Short-Term, Episodic, and Semantic Memory Systems]] — Расширение архитектуры памяти агента краткосрочной памятью на графах знаний.
- [[https://arxiv.org/abs/2305.10721][Revisiting Long-term Time Series Forecasting: An Investigation on Linear Mapping]] — Исследование доминирования аффинных преобразований в прогнозировании временных рядов.
- [[https://arxiv.org/abs/2401.03717][Universal Time-Series Representation Learning: A Survey]] — Обзор методов универсального представления временных рядов.
- [[https://arxiv.org/abs/2406.14427][Principles of frugal inference and control]] — Теория управления с учетом стоимости вывода и ресурсов.
- [[https://arxiv.org/abs/2408.17352][AASIST3: KAN-Enhanced AASIST Speech Deepfake Detection]] — Улучшенная модель детекции дипфейков речи с использованием KAN.
- [[https://arxiv.org/abs/2409.02428][Language Models as Efficient Reward Function Searchers for Custom-Environment Multi-Objective Reinforcement]] — Использование LLM для поиска функций вознаграждения в RL.
- [[https://arxiv.org/abs/2409.10102][Trustworthiness in Retrieval-Augmented Generation Systems: A Survey]] — Обзор доверия к RAG-системам по шести измерениям.

* TODO [2026-06-11 09:32:06] [llm] [ERROR] FAIL
DEADLINE: <2026-06-11 Thu 09:32>
:PROPERTIES:
:CREATED: [2026-06-11 09:32:06]
:END:
Error: Callback error: Invalid use of ‘\’ in replacement text

** Input
You are a Research Assistant monitoring arXiv preprints.
Target Audience: Graph & Data Systems Researcher.
Language: Russian.
Output Format: Org-mode.

Context:
Focus on Databases, Distributed Systems, Graph Algorithms, Network Analysis, and applied ML for systems.

CRITICAL OUTPUT RULES:
- Return ONLY raw Org-mode text.
- Do NOT use markdown, code fences, XML/JSON wrappers, or any commentary.
- Start directly with the first Org heading.
- Follow Org heading syntax strictly.

Task:
1. Group papers by arXiv categories: cs.DB (Databases), cs.AI (Artificial Intelligence), physics.soc-ph (Social Physics & Networks), cs.DS (Data Structures & Algorithms), cs.DC (Distributed Computing).
2. For each non-empty category, generate the following structure:

* <Category Name>
** 🧐 Обзор
2-4 sentences on trend for the last 1 days: what is new, what is maturing, what is practically relevant.

** 🛠 Практика и Системы
- [[<Link>][<Title>]]
:WHAT: What system/optimization/method is introduced.
:IMPACT: Why it matters in practice.

** 🕸 Графы и Алгоритмы
- [[<Link>][<Title>]]
:ALGO: Key algorithmic or modeling contribution.
:IMPACT: Why it matters for graph/data systems.

** 📄 Остальное
- [[<Link>][<Title>]] — one concise sentence.

Selection constraints:
- Prioritize papers with clear system impact or strong algorithmic contribution.
- Deprioritize purely theoretical work unless it has plausible practical/system relevance.
- Omit empty subsections if no papers match.
- Omit empty categories.

Data:
Title: LLMpedia: A Transparent Framework to Materialize an LLM's Encyclopedic Knowledge at Scale
Link: https://arxiv.org/abs/2603.24080
Tags: arxiv, csdb
Abstract/Content: arXiv:2603.24080v2 Announce Type: replace-cross Abstract: Benchmarks like MMLU suggest flagship language models approach factuality saturation above 90\%. \emph{LLMpedia} shows this picture is incomplete. We materialize ${\sim}$1.3M encyclopedia articles entirely from parametric memory across three model families, then audit every claim against Wikipedia and curated web evidence. For \texttt{gpt-5-mini}, the verifiable true rate is 68.4\% on Wikipedia-covered subjects - more than 21\,pp below MMLU - and the gap is driven by \emph{unverifiability} (30.5\%), not refutation (1.2\%). Beyond Wikipedia, frontier articles audited against curated web evidence reach 57.6\%; Wikipedia covers only 56.7\% of model-surfaced subjects, and three model families overlap in just 7.3\% of subject choices. In a retrieval-trap benchmark inspired by prior analysis of Grokipedia, LLMpedia is more factual at roughly half the textual similarity to Wikipedia. Every prompt, article, and verdict is released. Data, code, interface: https://llmpedia.net.
---

Title: Foundations of the GraphAlg Language
Link: https://arxiv.org/abs/2604.11454
Tags: arxiv, csdb
Abstract/Content: arXiv:2604.11454v2 Announce Type: replace Abstract: The GraphAlg domain-specific language for graph algorithms enables user-defined algorithms in graph databases. In this work we show how GraphAlg is built on top of the formal MATLANG language for matrix manipulation. Starting from MATLANG, we describe the extensions to MATLANG and the syntactic sugar needed to derive GraphAlg. Furthermore, we prove that any GraphAlg program can be simulated in an extension of for-MATLANG that supports simultaneous induction.
---

Title: RUBICON: Agentic AI for Messy Enterprise Data
Link: https://arxiv.org/abs/2604.21413
Tags: arxiv, csdb
Abstract/Content: arXiv:2604.21413v2 Announce Type: replace Abstract: Enterprise data exists in many forms, such as tables, text, maps, e-mail, and CAD models, that are access-controlled and hidden behind bespoke interfaces. Current agentic AI systems delegate the entire query workflow to a frontier LLM: a single model interprets the request, selects sources or tools, integrates retrieved evidence, judges completeness, and generates an answer, with few constraints, limited use of schemas, and text as the primary representation throughout. We argue that this is an ineffective abstraction for enterprise data. Reliable agentic AI should instead require structure: a constrained query interface over each source and a table-centric integration layer driven by a query processor. We introduce RUBICON, a system that embodies this vision. RUBICON is based on two observations. First, text-to-SQL fails on real enterprise data and must be dramatically subsetted to achieve reliable results. Second, data integration across disparate corporate datasets is best performed using tables as the core abstraction rather than text-centric LLM pipelines. We evaluate RUBICON on two benchmarks: our enterprise-focused RUBICON-Bench, against agentic baselines, and SemBench, against LOTUS and Palimpzest. On RUBICON-Bench, where queries require coordination across heterogeneous enterprise sources, RUBICON achieves 100% end-to-end accuracy, while all agentic baselines, including single- and multi-agent ReAct systems, produce no correct answers. On SemBench, RUBICON surpasses both LOTUS and Palimpzest: it achieves 14.7% higher accuracy, reduces latency by 62.64%, and lowers token cost by 98.64%, demonstrating that a table-centric architecture better matches enterprise data while yielding significant efficiency gains.
---

Title: TSseek: Regular Expression-Based Similarity Search for Distributed Time Series Datasets
Link: https://arxiv.org/abs/2606.09824
Tags: arxiv, csdb
Abstract/Content: arXiv:2606.09824v2 Announce Type: replace Abstract: Similarity search is a fundamental operation in time series analysis. Most existing techniques, however, require users to supply a precise sequence of values (typically an entire time series object) as the query input. This rigid requirement limits real-world applications, where users instead want to express patterns, trends, or value ranges. Flexible, pattern-based search has been explored in text retrieval and complex event processing, but remains underexplored for large-scale distributed time series. To close this gap, we propose TSseek, a regular-expression-powered search framework for distributed time series datasets. TSseek's query language enables users to compose patterns encompassing trends, value ranges, and wildcard segments. We show that conventional approximation techniques (e.g., PAA and SAX) and their index structures are ill-suited for such queries because they cannot operate on regular-expression query constructs. In TSseek, we map the time series objects and the query constructs into the same space by approximating time series objects as sequences of line segments that retain both trend (slope direction) and value range, and translating query constructs into bounding rectangles. To support efficient processing, we build TSseek-X, a distributed spatial index over the time series segments. TSseek supports two fundamental query types, namely whole-matching queries (over entire series) and subsequence-matching queries (over arbitrary windows within a series). Across benchmark and real-world datasets, full-scan, model-based, and SAX-based baselines all sacrifice either accuracy or speed, whereas TSseek returns exact answers efficiently. Also, for subsequence workloads, it achieves significant speedups over state-of-the-art subsequence matching engines.
---

Title: Few-Shot Resampling for Scalable Statistically-Sound Data Mining
Link: https://arxiv.org/abs/2606.11235
Tags: arxiv, csdb
Abstract/Content: arXiv:2606.11235v1 Announce Type: cross Abstract: A key step in knowledge discovery is the evaluation of data mining results. In several applications, including pattern mining, graph analysis, and others, this step includes the evaluation of the statistical significance of the results, to avoid spurious discoveries due only to noise or random fluctuations in the data. While specialized procedures have been developed for some specific applications, resampling-based approaches are widely used, in particular for complex analyses where analytical results cannot be derived. However, current resampling-based approaches require the generation and analysis of thousands of resampled datasets, and are therefore impractical for large datasets or computationally intensive analyses. In this paper, we introduce FewRS, a simple and effective resampling-based approach to assess the statistical significance of data mining results with rigorous guarantees on the probability of false discoveries. Our approach can be used in every situation where resampling-based approaches are applied. FewRS builds on our derivation of a novel bound to the supremum deviation of test statistics representing the quality of data mining results. We prove that FewRS needs to generate and analyze an extremely small number of resampled datasets, leading to a highly scalable approach with wide applicability. We test our approach on common tasks such as pattern mining and network analysis. In all cases, our approach results in a reduction of up to two orders of magnitude in running time compared to the state of the art, while preserving high statistical power, enabling the statistical validation of data mining results on large-scale real-world datasets.
---

Title: Querying Cohesive Subgraph regarding Span-Constrained Triangles on Temporal Graphs with Dynamic Index Maintenance
Link: https://arxiv.org/abs/2606.11582
Tags: arxiv, csdb
Abstract/Content: arXiv:2606.11582v1 Announce Type: new Abstract: Recent advances in temporal graph research have redefined traditional static graph concepts such as triangles, motifs, and $k$-cores. Inspired by this, we introduce a novel $(k,\delta)$-truss for temporal graphs, requiring triangles to exist within sufficiently short time windows. The $(k,\delta)$-truss ensures both static and temporal cohesion, while the original $k$-truss is a special case when $\delta = \infty$. To address $(k,\delta)$-truss queries, we propose index-free and index-based approaches. Utilizing the dual containment relation of $(k,\delta)$-trusses, our indexes losslessly compress all $(k,\delta)$-trusses into map or tree structures, significantly reducing space while enabling optimal-time retrieval. To scale to large temporal graphs, we develop two index construction algorithms based on truss decomposition and truss maintenance, respectively, which substantially reduce redundant computations. Moreover, we present techniques for the dynamic maintenance of the proposed indexes. The experimental results demonstrate that index-based approaches process queries in interactive time and outperform the index-free approach by 2$\sim$4 orders of magnitude, while the indexes achieve compression ratios of up to $10^{-4}$ and can be updated efficiently without rebuilding from scratch.
---

Title: Efficient Graph Indexing for Interval-Aware Vector Search
Link: https://arxiv.org/abs/2606.11789
Tags: arxiv, csdb
Abstract/Content: arXiv:2606.11789v1 Announce Type: new Abstract: Interval-aware Approximate Nearest Neighbor (ANN) search arises in applications where each object is associated with a numeric value or interval, and queries must satisfy both vector-similarity and interval constraints. Existing methods are typically tailored to a single query semantics, such as interval-filtered ANN search, and therefore require multiple specialized indexes to support diverse workloads, leading to substantial indexing and memory overhead. To address this limitation, we propose the Unified Interval-aware Relative Neighborhood Graph (URNG), a unified graph framework for interval-aware ANN search. URNG preserves the monotonic searchability of relative-neighborhood-graph based ANN indexes while additionally ensuring structural heredity over query-induced subgraphs, enabling a single index to support multiple interval-aware query semantics. Building on this framework, we develop UG, a practical graph index that efficiently approximates URNG through unified interval-aware pruning and iterative repair, together with a query algorithm for interval-aware ANN search. Extensive experiments on 5 datasets show that UG consistently achieves a strong accuracy-efficiency trade-off across diverse interval-aware workloads while maintaining competitive index construction cost and memory usage.
---

Title: Neuro-Relational Programs: Unifying Queries and Neural Computation over Structured Data
Link: https://arxiv.org/abs/2606.11946
Tags: arxiv, csdb
Abstract/Content: arXiv:2606.11946v1 Announce Type: new Abstract: The conventional approach to deep learning over relational databases applies neural models, such as Graph Neural Networks (GNNs), to a graph representation of the database. Recent approaches instead operate on databases directly, associating tuples with embeddings and extending query mechanisms to jointly process embeddings and relational content. Inspired by these developments, we introduce Neuro-Relational Programs (NRPs), a declarative query language for relational databases whose facts carry numeric vector embeddings. NRPs extend Datalog-style rules with operations that combine, aggregate, and transform embeddings, thereby interleaving relational reasoning and learnable neural components within a single formalism. This yields a general approach to neural computation over relational data: an NRP can be read both as a query plan with trainable components and as a neural architecture with relational structure built in. Natural syntactic fragments of NRPs recover existing architectures and query formalisms. Zero-ary NRPs correspond to non-adaptive query algorithms; monadic NRPs generalize GNN-style message passing and precisely capture Deep Homomorphism Networks, a connection that we extend to frontier-guarded NRPs over databases with row-ids. We characterize the expressive power of unrestricted NRPs with ReLU-FFN transformations by FOCQ, an extension of first-order logic with counting interpreted over real-weighted structures, yielding a precise connection with uniform TC$^0$ over ordered databases. Together, these results establish NRPs as a broad declarative framework for querying and neural computation over relational data.
---

Title: First Order Logic on Pathwidth Revisited Again
Link: https://arxiv.org/abs/2210.09899
Tags: arxiv, csds
Abstract/Content: arXiv:2210.09899v5 Announce Type: replace Abstract: Courcelle's celebrated theorem states that all MSO-expressible properties can be decided in linear time on graphs of bounded treewidth. Unfortunately, the hidden constant implied by this theorem is a tower of exponentials whose height increases with each quantifier alternation in the formula. More devastatingly, this cannot be improved, under standard assumptions, even if we consider the much more restricted problem of deciding FO-expressible properties on trees. In this paper we revisit this well-studied topic and identify a natural special case where the dependence of Courcelle's theorem can, in fact, be improved. Specifically, we show that all FO-expressible properties can be decided with an elementary dependence on the input formula, if the input graph has bounded pathwidth (rather than treewidth). This is a rare example of treewidth and pathwidth having different complexity behaviors. Our result is also in sharp contrast with MSO logic on graphs of bounded pathwidth, where it is known that the dependence has to be non-elementary, under standard assumptions. Our work builds upon, and generalizes, a corresponding meta-theorem by Gajarsk\'y and Hlin\v{e}n\'y for the more restricted class of graphs of bounded tree-depth.
---

Title: U-HNSW: An Efficient Graph-based Solution to ANNS Under Universal Lp Metrics
Link: https://arxiv.org/abs/2605.02030
Tags: arxiv, csdb
Abstract/Content: arXiv:2605.02030v3 Announce Type: replace-cross Abstract: Approximate nearest neighbor search under universal L_p metrics (ANNS-U-L_p) is an important and challenging research problem, as it requires answering queries under all possible p (0<p <= 2) values simultaneously without building an index for each possible p value. The state-of-the-art solution, called MLSH, is a Locality-Sensitive Hashing (LSH)-based ANNS method with barely acceptable query performance. In contrast, graph-based ANNS methods, which offer significantly improved query efficiency on the ANNS-L_p problem (with a fixed p-value), cannot be naively extended to the ANNS-U-$L_p$ problem. In this paper, we propose U-HNSW, the first graph-based method for ANNS-U-L_p. Our scheme uses HNSW graph indexes built on two base metrics ($L_1$ and $L_2$) to generate promising nearest neighbors candidates, and then verifies these candidates with an early-termination strategy that substantially reduces the number of expensive L_p distance computations. Experimental results show that U-HNSW not only achieves up to 2670 times shorter query times than the original MLSH implementation running on a RAM disk (up to 15 times shorter than the idealized MLSH), but also outperforms the original HNSW on the ANNS-L_p problem (with a fixed p-value), except for a few special p values.
---

Title: The World's Fastest Matching Engine Algorithm
Link: https://arxiv.org/abs/2606.01183
Tags: arxiv, csdb
Abstract/Content: arXiv:2606.01183v3 Announce Type: replace-cross Abstract: A single CPU core sustains 32 million order messages per second at sub-microsecond median end-to-end host-path response latency, 4.7-11 times faster than the best available open-source matching engines on identical hardware. Scaled out, a single 96-core commodity server (~$1,630/month) sustains ~640 million messages per second across 10,000 symbols, over 20 times the provisioned capacity of the U.S. consolidated quote feed. We reach these numbers by attacking the storage layer that sets matching latency. The dominant order-book implementation, linked lists chained through a balanced tree, imposes two costs on every operation: pointer-chased traversal to the insertion point, and root-to-leaf search to locate the target price level. Under micro-bursts these costs produce tail-latency spikes that degrade market quality precisely when liquidity is most needed. We present two data-structure contributions that eliminate them. The first is the Priority-Indicated Node (PIN), a priority queue in which entries occupy fixed-capacity, contiguously addressable slots, with indicators encoding the entry's global priority status. Unlike heaps, which require O(log n) comparisons per operation, the PIN resolves insertion position directly from the indicators without comparing entries; indicator updates are O(1), independent of queue size. A depth-aware capacity model sizes each PIN so hot entries fit within L1 residency. The second targets a broader inefficiency: balanced search trees search from root to leaf on every insertion and deletion, even when the caller already knows the key's in-order neighbors, which in electronic trading are available at zero cost. Neighbor-aware insertion and deletion use known neighbor references to attach or remove a node with O(1) reference writes, followed by single-path rebalancing, across red-black, AVL, and B+-tree variants.
---

Title: Fixed-Parameter Tractability of Private Synthetic Data Generation
Link: https://arxiv.org/abs/2606.11283
Tags: arxiv, csds
Abstract/Content: arXiv:2606.11283v1 Announce Type: new Abstract: We study the problem of generating synthetic data under differential privacy. We establish fixed-parameter tractability (FPT) for this problem where the parameter is the treewidth of the query family's incidence graph. Our algorithms attain optimal error rates across all regimes and are realized by two different approaches: the first is based on linear programming (LP) and the FPT of the separation problem for the LP dual; the second is based on a subsampled private multiplicative weights method, where we obtain FPT for sampling from Gibbs distributions. Both approaches are unified by a dynamic programming framework over a tree decomposition.
---

Title: The Power of Test-Time Training for Approximate Sampling
Link: https://arxiv.org/abs/2606.11437
Tags: arxiv, csai
Abstract/Content: arXiv:2606.11437v1 Announce Type: new Abstract: Efficiently sampling from a complex probability distribution is a fundamental problem which has become increasingly pertinent in recent years with the rise of generative AI, as sophisticated sampling procedures from LLMs have been proposed to solve challenging reasoning problems. The efficacy of such sampling algorithms is limited, however, by the relationship between the LLM and the particular sampling task at hand, which has motivated the framework of test-time training (TTT). TTT works by updating a model's weights in response to partial generations and reward feedback received at inference time, thus adapting to the particular problem. In this work, we propose a formalization for TTT as the problem of producing a sample from a given probability measure $\mu^\star$ belonging to a known class ${F}$ of distributions, given an oracle $\hat \mu$ which yields approximate density estimates for $\mu^\star$. This is closely related to the problem of reducing sampling to approximate counting studied in seminal works of Jerrum, Valiant & Vazirani (1986) and Jerrum & Sinclair (1989): namely, when ${F}$ is the class of all distributions, it coincides exactly with the aforementioned counting-to-sampling reduction. In this paper, we first show a quadratic lower bound on the query complexity of sampling from $\mu^\star$ given query access to $\hat \mu$ (for sufficiently large classes ${F}$), thus showing that the random walk approach proposed by Jerrum & Sinclair (1989) and refined by Hayes & Sinclair (2010), is optimal. This answers an open question posed by Hayes & Sinclair. We then show that this lower bound can be circumvented if the size of ${F}$ is bounded appropriately. As we discuss, this latter result can be viewed as an abstraction of TTT, and thus represents a starting point for the development of a principled theoretical framework for TTT.
---

Title: A Unified Lower Bound on the Noisy Query Complexity of Boolean Functions
Link: https://arxiv.org/abs/2606.11448
Tags: arxiv, csds
Abstract/Content: arXiv:2606.11448v1 Announce Type: new Abstract: We study the query complexity of Boolean functions $f: \{0, 1\}^n \rightarrow \{0, 1\}$ in the noisy query model introduced by Feige, Raghavan, Peleg and Upfal [SICOMP 1994]. In this model, an algorithm can adaptively query the bits of an input vector, but each query result is independently flipped with constant probability $p \in (0, 1/2)$; repeated queries are allowed. The noisy query complexity $\mathsf{N}_p(f)$ of a function $f$ is defined as the minimum expected number of queries needed to compute $f(x)$ with error probability at most $1/3$, for the worst case input $x$. We prove a general lower bound on $\mathsf{N}_p(f)$ based on degree statistics of certain subgraphs of the Boolean hypercube. This is the first general lower bound beyond those implied by the simple observation that $\mathsf{N}_p(f)$ is lower bounded by the randomized query complexity. We show that this recovers (up to a constant factor) most previously known lower bounds on the noisy query complexity of Boolean functions, providing a unified framework for understanding these results and simplifying the proofs in several cases. Furthermore, this resolves in the affirmative an open problem of Gu, Li and Xu [COLT 2025] that $\mathsf{N}_p(f) = \Omega(\mathsf{I}(f) \log \mathsf{I}(f))$, where $\mathsf{I}(f)$ denotes the total influence of $f$. We also apply our general lower bound to obtain tight bounds on the noisy query complexity for several new functions.
---

Title: Density estimation for Hellinger via minimum-distance estimators: mixtures of Gaussians, log-concave, and more
Link: https://arxiv.org/abs/2606.11469
Tags: arxiv, csds
Abstract/Content: arXiv:2606.11469v1 Announce Type: new Abstract: We study the task of density estimation, where we hope to accurately estimate a probability density from $n$ samples. A textbook method for density estimation in total variation distance is the minimum-distance estimator approach, where we conclude both the algorithm and the analysis merely from bounding the VC dimension of a particular concept class (the so-called Yatracos class). While this technique has originally yielded sharp guarantees primarily for total variation distance, in this work we extend the minimum-distance estimator approach for learning within Hellinger distance. Our main observation is that we may produce an analogous recipe for Hellinger (where we only require bounding the VC dimension of a related concept class) by drawing connections to recent results yielding reverse data processing inequalities. This recipe is flexible enough to accommodate fast algorithms originally designed for total variation distance; by modifying the approach of Acharya et al. (2017) we conclude the first near-linear time algorithm for learning classes including univariate mixtures of log-concave densities and mixtures of Gaussians (with arbitrary variances), with near-optimal sample complexity.
---

Title: Beyond Frequency Marching: Orbit Recovery in Dihedral and Projected Multireference Alignment
Link: https://arxiv.org/abs/2606.11701
Tags: arxiv, csds
Abstract/Content: arXiv:2606.11701v1 Announce Type: new Abstract: Multireference alignment (MRA) is the task of recovering a hidden "signal" vector, given many noisy copies that have been cyclically shifted by unknown offsets. This task belongs to the class of orbit recovery problems, in which the observed samples are affected by some group action. These problems have a variety of practical motivations, including the reconstruction of 3-dimensional molecular structure from cryogenic electron microscopy (cryo-EM) images. We consider two variants of MRA: dihedral MRA, where the cyclic group is replaced by the dihedral group, allowing for reversals of the vector in addition to shifts; and projected MRA, where the observations are passed through a projection operator akin to the tomographic projection present in cryo-EM. We apply the method of moments and aim to recover the signal from the third moment tensor of the samples. This inverse problem is well understood for basic MRA, but for the variants we consider there is no polynomial-time algorithm known to succeed for generic signals. We give the first such algorithm for both of these variants. Our method requires the signal length to be a power of two, and recursively subdivides the problem into smaller problems of half the size. The algorithm's success for generic signals is proven, conditional on a conjecture about the rank of a certain symbolic matrix of polynomials. For any given problem size, this conjecture can be verified on a computer.
---

Title: A Fast Gaussian Mechanism under Continual Observation, with Applications
Link: https://arxiv.org/abs/2606.11760
Tags: arxiv, csdb
Abstract/Content: arXiv:2606.11760v1 Announce Type: new Abstract: We consider the problem of privately releasing a $k$-dimensional vector under updates: Starting with a zero vector, at times $t_1, t_2,\dots$ the vector is updated by adding $x^{(1)}, x^{(2)},\dots$, respectively. For positive integers $T$, $k$ we model the updates as a data set $\{(t_i, x^{(i)})\}_i$, where $t_i \in [T]$ and $x^{(i)} \in B_k$ (the $k$-dimensional unit ball). Two such data sets are said to be neighboring if their symmetric difference has size at most $1$. The continual release consists of the sum $A^{(t)} = \sum_{i \; : \; t_i \leq t} x^{(i)}$ for each time step $t=1,\dots,T$. Classical continual release techniques allow us to release an approximation of $A^{(1)},\dots,A^{(T)}$ with additive noise of magnitude $\text{polylog}(T)$, computed in time $O(kT)$, even in the on-line, adaptive case where data is continually revealed for the current time step. Motivated by private sketching techniques, we consider the setting where only a \emph{subset} of entries in $A^{(t)}$ need to be released at time step $t$. Our new result is that it is possible to sample any desired entry in a given noise vector in \emph{constant time} while reproducing exactly the distribution of the binary tree mechanism with Gaussian noise. The improvement on the known time bound of $O(\log T)$ comes from a new data structure that allows us to sample a new noise value with the correct correlations in constant time using Brownian bridges. We present two data management applications, of independent interest, that use our technique in conjunction with differentially private CountSketches: 1) A dynamic data structure for orthogonal range counting queries with a better privacy/accuracy/space trade-off than previous data structures, and 2) Join size estimation, where in addition we show improved high-probability bounds.
---

Title: On finding exact solutions of linear programs in the oracle model
Link: https://arxiv.org/abs/2606.11820
Tags: arxiv, csds
Abstract/Content: arXiv:2606.11820v1 Announce Type: cross Abstract: We consider linear programming in the oracle model: $\max\{c^\top x \,:\, x\in P\}$, where the polyhedron $P=\{x\in\mathbb{R}^n\,:\, Ax\le b\}$ is given by a separation oracle. We present an algorithm that finds exact primal and dual solutions using $O(n^2\log(n/\delta))$ oracle calls and $O(n^4\log(n/\delta)+n^5\log\log(1/\delta))$ arithmetic operations, where $\delta$ is a geometric condition number associated with the system $(A,b)$. These bounds do not depend on the cost vector $c$ and do not require a priori knowledge of $\delta$. For rational data, $\log(1/\delta)$ is polynomially bounded in the encoding size of $(A,b)$, thus providing a polynomial-time algorithm. The algorithm works in a black box manner, requiring a subroutine for approximate primal and dual solutions; the above running times are achieved when using the cutting plane method of Jiang, Lee, Song, and Wong (STOC 2020) for this subroutine. Whereas approximate solvers may return primal solutions only, we develop a general framework for extracting dual certificates based on the work of Burrell and Todd (Math. Oper. Res. 1985). Our algorithm strengthens results by Gr\"otschel, Lov\'asz, and Schrijver (Prog. Comb. Opt. 1984), and by Frank and Tardos (Combinatorica 1987) that rely on bit-complexity arguments. Our algorithm avoids rounding-based arguments such as simultaneous Diophantine approximation and uses geometric arguments instead.
---

Title: Consensus on Dynamic Stochastic Block Models: Fast Convergence and Phase Transitions
Link: https://arxiv.org/abs/2209.03999
Tags: arxiv, csdc
Abstract/Content: arXiv:2209.03999v2 Announce Type: replace-cross Abstract: We introduce two models of consensus following a majority rule on time-evolving stochastic block models (SBM), in which the network evolution is Markovian or non-Markovian. Under the majority rule, in each round, each agent simultaneously updates their opinion according to the majority of their neighbors. Our network has a community structure and randomly evolves with time. In contrast to the classic setting, the dynamics is not purely deterministic, and reflects the structure of SBM by resampling the connections at each step, making agents with the same opinion more likely to connect than those with different opinions. In the Markovian model, connections between agents are resampled at each step according to the SBM law and each agent updates their opinion via the majority rule. We prove a power-of-one type result, i.e., any initial bias leads to a non-trivial advantage of winning in the end, uniformly in the size of the network. In the non-Markovian model, a connection between two agents is resampled according to the SBM law only when at least one of them changes opinion and is otherwise kept the same. We identify the phase-transition threshold, up to the second-order leading term, between halting and fast convergence to consensus. We also give sufficient initial-lead conditions for consensus to occur within one, two, or three rounds.
---

Title: Impossibility Results for Strong Linearizability: The Difficulty of Consistent Refereeing
Link: https://arxiv.org/abs/2506.18401
Tags: arxiv, csdc
Abstract/Content: arXiv:2506.18401v3 Announce Type: replace Abstract: This paper studies the relation between agreement and strongly linearizable implementations of various objects. This leads to new results about implementations of concurrent objects from various primitives including window registers, interfering primitives and stacks. We identify that lock-free, respectively, wait-free, strongly linearizable implementations of several concurrent objects entail a form of agreement that does not require full consensus but cannot be implemented in a strongly-linearizable manner with combinations of non-universal primitives. In both cases, lock-free and wait-free, this form of agreement requires a distinguished process to referee a competition that involves all other processes. Our results show that consistent refereeing of such competitions (i.e., once resolved, the outcome cannot be revised in any extension of the execution) requires high coordination power. More specifically, two contest objects are defined and used to help characterize coordination constraints imposed by strong linearizability in lock-free and wait-free implementations, respectively. Both objects are strictly weaker than consensus, in the sense that they have a wait-free linearizable (in fact, decisively linearizable) implementation from reads and writes. The contest objects capture strong linearizability in two complementary ways. First, they admit strongly linearizable implementations from several high-level objects such as queues, snapshots, and counters, so impossibility results for the contest objects immediately carry over to these objects. Second, they admit powerful impossibility results for strong linearizability that involve window registers, interfering primitives and stacks, which are non-universal.
---

Title: Energy Use of AI Inference, Efficiency Pathways, and Test-Time Scaling
Link: https://arxiv.org/abs/2509.20241
Tags: arxiv, csdc
Abstract/Content: arXiv:2509.20241v2 Announce Type: replace-cross Abstract: As AI inference scales to billions of queries, estimates of per-query energy use are increasingly important for capacity planning, efficiency interventions, and policy. Yet many public estimates assume non-production settings, leading to systematic overestimation. We introduce a bottom-up framework estimating inference energy from token throughput, node power, and overhead under large-scale deployment assumptions. For frontier-scale models (>200B parameters) on H100 nodes, we estimate a median energy of 0.31 Wh/query (IQR 0.16-0.60), indicating widely cited estimates are overstated by 4-20x. In test-time scaling scenarios 15x longer than typical queries, the median energy rises 13x to 3.91 Wh (IQR 2.15-7.05). Across models, serving systems, and hardware, we estimate 8-20x line-of-sight energy reductions. At datacenter scale, serving 1 billion queries/day requires 0.7 GWh; if 10% are long queries, demand rises to 1.7 GWh/day. With efficiency interventions, it falls to 0.8 GWh/day, mitigating the energy impact of test-time scaling.
---

Title: A New Broadcast Model for Several Network Topologies
Link: https://arxiv.org/abs/2510.18058
Tags: arxiv, csdc
Abstract/Content: arXiv:2510.18058v3 Announce Type: replace-cross Abstract: We introduce Broadcast by Balanced Saturation (BBS), a general class of tree-based pipelined broadcast algorithms that optimizes communication efficiency across diverse network topologies, with a particular emphasis on large message sizes. By addressing spanning tree construction and communication task scheduling, two fundamental theoretical challenges in broadcasting, BBS offers a unified and flexible framework that operates effectively under varied network constraints. The algorithm maximizes aggregated throughput while simultaneously addressing topology constraints, synchronization overhead, bandwidth limitations and contention. Using SimGrid under standard assumptions, including full-duplex and one-port communication, various algorithms were evaluated on Mesh, Butterfly, Dragonfly, and Fat-Tree topologies. Results demonstrate that BBS consistently outperforms both general-purpose and topology-aware broadcast algorithms across a wide range of topologies and message sizes, establishing it as a robust and high-performance solution for large-scale systems.
---

Title: SEDULity: A Proof-of-Learning Framework for Distributed and Secure Blockchains with Efficient Useful Work
Link: https://arxiv.org/abs/2512.13666
Tags: arxiv, csdc
Abstract/Content: arXiv:2512.13666v2 Announce Type: replace-cross Abstract: The security and decentralization of Proof-of-Work (PoW) have been well-tested in existing blockchain systems. However, its tremendous energy waste has raised concerns about sustainability. Proof-of-Useful-Work (PoUW) aims to redirect the meaningless computation to meaningful tasks such as solving machine learning (ML) problems, giving rise to the branch of Proof-of-Learning (PoL). While previous studies have proposed various PoLs, they all, to some degree, suffer from security, decentralization, or efficiency issues. In this paper, we propose a PoL framework that trains ML models efficiently while maintaining blockchain security in a fully distributed manner. We name the framework SEDULity, which stands for a Secure, Efficient, Distributed, and Useful Learning-based blockchain system. Specifically, we encode the template block into the training process and design a useful function that is difficult to solve but relatively easy to verify, as a substitute for the PoW puzzle. We show that our framework is distributed, secure, and efficiently trains ML models. We further demonstrate that the proposed PoL framework can be extended to other types of useful work and design an incentive mechanism to incentivize task verification. We show theoretically that a rational miner is incentivized to train fully honestly with well-designed system parameters. Finally, we present simulation results to demonstrate the performance of our framework and validate our analysis.
---

Title: MPK: A Compiler and Runtime for Mega-Kernelizing Tensor Programs
Link: https://arxiv.org/abs/2512.22219
Tags: arxiv, csdc
Abstract/Content: arXiv:2512.22219v2 Announce Type: replace Abstract: We introduce Mirage Persistent Kernel (MPK), the first compiler and runtime system that automatically transforms multi-GPU model inference into a single high-performance mega-kernel. MPK introduces an SM-level graph representation that captures data dependencies at the granularity of individual streaming multiprocessors (SMs), enabling cross-operator software pipelining, \rev{fine-grained overlap of computation and communication, and other optimizations that are infeasible under the conventional kernel-per-operator execution model}. The MPK compiler lowers tensor programs into optimized SM-level task graphs and generates fast CUDA implementations for each task, while the MPK in-kernel parallel runtime executes these tasks within a single persistent mega-kernel using decentralized scheduling across SMs. Together, these components provide end-to-end kernel fusion with minimal developer effort, while preserving the flexibility of existing programming models. Our evaluation shows that MPK significantly outperforms existing kernel-per-operator LLM serving systems, achieving up to 1.7$\times$ lower end-to-end inference latency and pushing LLM inference performance close to the limits of the underlying hardware. MPK is publicly available at https://github.com/mirage-project/mirage.
---

Title: LCLs Beyond Bounded Degrees
Link: https://arxiv.org/abs/2602.02340
Tags: arxiv, csdc
Abstract/Content: arXiv:2602.02340v3 Announce Type: replace Abstract: The study of Locally Checkable Labelings (LCLs) has led to a remarkably precise characterization of the distributed time complexities that can occur on bounded-degree trees. A central feature of this complexity landscape is the existence of gap results, which rule out large ranges of intermediate complexities. While it was initially hoped that these gaps might extend to more general graph classes, this has turned out not to be the case. In this work, we investigate a different direction: we remain in the class of trees, but allow arbitrarily large degrees. We focus on the polynomial regime, i.e. complexities of the form $\Theta(n^{1/k})$ for $k \in \mathbb{N}$, and show that whether polynomial gap results persist in the unbounded-degree setting crucially depends on how LCLs are generalized beyond bounded degrees. There already exists a complex construction that shows that the polynomial gaps also vanish for LCLs on unbounded-degree trees. Rather than stopping at this negative result, we give a much simpler set of problems that already contradicts the existence of any polynomial gaps. The insight obtained from this cleaner construction is that for gap results to exist, we cannot allow problem definitions to distinguish infinitely many local cases. Inspired by this, we introduce Locally Finite Labelings (LFLs), which formalize the intuition that every node must fall into one of finitely many local cases. Our main result shows that this restriction is sufficient to restore the polynomial gaps: for any LFL $\Pi$ on trees with unbounded degrees, the deterministic LOCAL complexity of $\Pi$ is either - $\Theta(n^{1/k})$ for some integer $k \geq 1$, or - $O(\log n)$. Moreover, which case applies, and the corresponding value of $k$, can be determined solely from the description of $\Pi$.
---

Title: Ensuring Data Freshness in Multi-Rate Task Chains Scheduling
Link: https://arxiv.org/abs/2603.09738
Tags: arxiv, csdc
Abstract/Content: arXiv:2603.09738v2 Announce Type: replace-cross Abstract: In safety-critical autonomous systems, data freshness presents a fundamental design challenge. While the Logical Execution Time (LET) paradigm ensures compositional determinism, it often does so at the cost of injected latency, possibly degrading the age of data on high-frequency control loops. Furthermore, heterogeneous, multi-rate, task dependencies is typically guaranteed inefficiently through oversampling. This paper proposes a Task-based scheduling framework extended with data freshness constraints. Unlike traditional models, scheduling decisions are driven by the lifespan of data. We introduce a formal methodology to decompose Data Dependency Graphs into dominant paths by tracing the strictest data freshness constraints backward from the actuators. Based on this decomposition, we propose an offset search algorithm that synchronizes multi-rate, multi-dependencies, task chains. This approach enforces end-to-end data freshness without the artificial latency of LET buffering, a trade-off between data freshness and execution determinism. We formally prove that this offset-based alignment preserves the 100% schedulability capacity of Global EDF while addressing data freshness guarantees.
---

Title: LLM-Enhanced Deep Reinforcement Learning for Task Offloading in Collaborative Edge Computing
Link: https://arxiv.org/abs/2605.05727
Tags: arxiv, csdc
Abstract/Content: arXiv:2605.05727v2 Announce Type: replace Abstract: Collaborative edge computing uses edge nodes in different locations to execute tasks, necessitating dynamic task offloading decisions to maintain low latency and high reliability, especially under unpredictable node failures. Although deep reinforcement learning (DRL) and large language models (LLMs) have shown promise for task offloading, DRL often suffers from poor sample efficiency and local optima, while LLMs are difficult to use directly due to inference overhead and output uncertainty. To address these limitations, we propose \textbf{LeDRL}, a hybrid decision framework that couples a \emph{lightweight LLM} with self-attention-enhanced DRL for real-time task offloading. LeDRL constructs structured, context-aware prompts capturing node status, task semantics, and link dynamics to derive high-level strategy priors. These are selectively processed by a self-attention-based alignment module for context-aware policy optimization. A reflective evaluator further distills semantic feedback from past trajectories to refine subsequent prompts and provide consistent guidance. Extensive experiments show that LeDRL outperforms representative baselines in task success rate, convergence speed, and real-time responsiveness across diverse network scales, achieving over 17\% improvement in success rate. Furthermore, we deploy LeDRL on Jetson-based edge devices using our prototype system \textit{CoEdgeSys}, demonstrating its robustness and feasibility under resource constraints. Our code is available at:https://github.com/GalleyG5/LeDRL.git.
---

Title: FalconGEMM: Surpassing Hardware Peaks with Lower-Complexity Matrix Multiplication
Link: https://arxiv.org/abs/2605.06057
Tags: arxiv, csdc
Abstract/Content: arXiv:2605.06057v4 Announce Type: replace Abstract: Peak breaking Matrix Multiplication is a promising technique to improve the performance of DL, especially in LLM training and inference. We present FalconGEMM, a cross-platform framework that automates the deployment, optimization, and selection of Lower-Complexity Matrix Multiplication Algorithms (LCMAs) across diverse hardware. There are three key innovations: (1) a Deployment Module that enables portable execution across various hardware and input configurations through code generation; (2) an Execution Module with Group-Parallel Optimizations that maximizes on-chip data reuse, utilizes parallel resources, and reduces bandwidth overhead; and (3) a Decision Module featuring a lightweight analytical performance model to select the optimal strategy based on matrix shapes and hardware profiles. Extensive evaluation is conducted on LLM workloads across GPU (H20, A100) and CPU (ARM, x86) architectures with multiple data types. FalconGEMM succeeds in delivering peak breaking performance and outperforms GEMM libraries (e.g., cuBLAS, CUTLASS, Intel MKL, etc) by 7.59%-17.85% and LCMA competitors like AlphaTensor by 12.41%-55.61%. Our framework makes the theoretical promise of LCMAs practical for production deployment across the heterogeneous landscape of modern hardware.
---

Title: Incivility in Public Health Policy Discussions Spills Over to Public Engagement with Climate Issues
Link: https://arxiv.org/abs/2502.05255
Tags: arxiv, socph
Abstract/Content: arXiv:2502.05255v3 Announce Type: replace-cross Abstract: Affective polarization and political sorting drive public antagonism around climate change and other issues at the science-policy nexus. We study cross-domain spillover of incivility in public engagements with climate change and public health on Twitter and Reddit using the COVID-19 period as a case study. We find strong evidence of the signatures of affective polarization surrounding COVID-19 spilling into the climate change domain. Across different social media systems, COVID-19 content is associated with incivility in climate discussions. These patterns of increased antagonism were responsive to pandemic events that made the link between science and public policy more salient. The observed spillover activated along pre-pandemic political cleavages, specifically anti-internationalist populist beliefs, that linked climate policy opposition to vaccine hesitancy. Our findings show how affective polarization in public engagement with science becomes entrenched across policy domains, which has implications for how the public engages with and communicates about issues such as climate change and public health.
---

Title: Collective decision-making with higher-order interactions on $d$-uniform hypergraphs
Link: https://arxiv.org/abs/2511.13452
Tags: arxiv, socph
Abstract/Content: arXiv:2511.13452v2 Announce Type: replace Abstract: Understanding how group interactions influence opinion dynamics is fundamental to the study of collective behavior. In this work, we propose and study a model of opinion dynamics on $d$-uniform hypergraphs, where individuals interact through group-based (higher-order) structures rather than simple pairwise connections. Each one of the two opinions $A$ and $B$ is characterized by a quality, $Q_A$ and $Q_B$, and agents update their opinions according to a general mechanism that takes into account the weighted fraction of agents supporting either opinion and the pooling error, $\alpha$, a proxy for the information lost during the interaction. Through bifurcation analysis of the mean-field model, we identify two critical thresholds, $\alpha_{\text{crit}}^{(1)}$ and $\alpha_{\text{crit}}^{(2)}$, which delimit stability regimes for the consensus states. These analytical predictions are validated through extensive agent-based simulations on both random and scale-free hypergraphs. Moreover, the analytical framework demonstrates that the bifurcation structure and critical thresholds are independent of the underlying topology of the higher-order network, depending solely on the parameters $d$, i.e., the size of the interaction groups, and the quality ratio. Finally, we bring to the fore a nontrivial effect: the large sizes of the interaction groups, could drive the system toward the adoption of the worst option.
---

Title: Three-dimensional Fundamental Diagrams of Five-neighbor Particle Cellular Automata
Link: https://arxiv.org/abs/2606.08972
Tags: arxiv, socph
Abstract/Content: arXiv:2606.08972v2 Announce Type: replace Abstract: We analyze five-neighbor particle cellular automata whose conventional two-dimensional fundamental diagrams are multivalued, but whose mean flow is uniquely determined by introducing a second density. We first consider binary rules for which the second density is conserved, and then examine rules for which the second density is not conserved but converges asymptotically. These examples give three-dimensional fundamental diagrams in which the mean flow is determined by the particle density and the second density. We then investigate whether this single-valued structure is preserved under real-valued max-plus extensions. There are some rules where two different max-plus extensions are introduced, and numerical simulations show that both extensions preserve the same single-valued three-dimensional fundamental diagram. These observations imply that, in constructing real-valued max-plus extensions, it is important to choose the flux function and the second density consistently.
---

Title: Emergent dilemma and periodic oscillation in the nonlinear interplay between epidemic and behavior
Link: https://arxiv.org/abs/2606.12013
Tags: arxiv, socph
Abstract/Content: arXiv:2606.12013v1 Announce Type: new Abstract: Human behaviors, particularly non-pharmaceutical interventions (NPIs), are dynamically coupled with epidemic spreading. While prior studies mainly assume a linear interplay, real-world behavioral evolution is driven by nonlinear responses and social influence. Here, we incorporate these multifaceted mechanisms into a co-evolutionary model and analytically derive the critical thresholds. Notably, as the infection rate grows, NPI compliance initially rises but then abruptly drops to zero. This paradoxical decline indicates an emergent social dilemma: at high infection rates, abandoning NPIs is individually optimal but detrimentally triggers an explosive surge in epidemic prevalence. We further show that socially induced overestimation of the infection rate can counterintuitively prompt individuals to abandon NPIs. Moreover, the interplay with social influence induces periodic oscillations, reflecting a tragic cycle of recurrent epidemic waves. Furthermore, we validate the robustness of this NPI-abandonment dilemma in networked population. Our work illustrates rich emergent phenomena in the co-evolution of epidemic and behavior, challenging traditional views on this coupled dynamics.
---

Title: Revealing Peri-Urban Dislocation through Percolation Analysis
Link: https://arxiv.org/abs/2606.12399
Tags: arxiv, socph
Abstract/Content: arXiv:2606.12399v1 Announce Type: new Abstract: This paper introduces peri urban dislocation as a structural condition that complements existing sprawl metrics by capturing hierarchical misalignments between inner city and peripheral areas. Whereas conventional measures emphasise density, land-use mix, or fragmentation, peri-urban dislocation reflects deeper divergences in the core periphery relational functional organisation of urban systems. We operationalise this concept using percolation analysis of street networks, revealing hierarchical patterns via clustering maps and dendrograms, providing a relational structure between urban elements. Two case studies, Valdivia, Chile, and Boston, USA, demonstrate contrasting manifestations: a structural reversal in Valdivia, where a homogeneous residential periphery dominates the hierarchical clustering process, and peri-urban voids in Boston, where isolated parcellations persist despite metropolitan consolidation. These findings position peri-urban dislocation as a structural dimension linked to sprawl yet distinct from metrics based on density or peripherality; one that may occur independently or represent a previously unidentified structural signature of sprawl. Methodologically, we apply established percolation techniques to expose this previously unarticulated structural phenomenon, enabling the detection of hierarchical misalignments within urban systems. Conceptually, we introduce peri urban dislocation as a new dimension of urban structure, helping articulate debates on sprawl and peri urbanisation through a complexity informed lens and enabling core periphery diagnostics across diverse urban contexts.
---

Title: LSTM based IoT Device Identification
Link: https://arxiv.org/abs/2304.13905
Tags: arxiv, csai
Abstract/Content: arXiv:2304.13905v2 Announce Type: replace-cross Abstract: While the use of the Internet of Things is becoming more and more popular, many security vulnerabilities are emerging with the large number of devices being introduced to the market. In this environment, IoT device identification methods provide a preventive security measure as an important factor in identifying these devices and detecting the vulnerabilities they suffer from. In this study, we present an end-to-end machine learning pipeline that identifies IoT devices in the Aalto university dataset (IoT devices captures) using Long Short-Term Memory (LSTM) networks. Raw network packet captures (PCAP) are processed into 25 engineered features, which are then arranged as sliding-window time-series sequences. We systematically evaluate sequence lengths from 2 to 20, reporting that performance improves approximately linearly up to length 6 and thereafter in a wave-like pattern, reaching its peak at length 18. On the final held-out test set with the optimal configuration, the model achieves an accuracy of 79.85% and a macro-averaged F1-score of 75.70% across 27 device classes.
---

Title: Improving Generalization and Data Efficiency with Diffusion in Offline Multi-agent RL
Link: https://arxiv.org/abs/2307.01472
Tags: arxiv, csai
Abstract/Content: arXiv:2307.01472v2 Announce Type: replace Abstract: We present a novel Diffusion Offline Multi-agent Model (DOM2) for offline Multi-Agent Reinforcement Learning (MARL). Different from existing algorithms that rely mainly on conservatism in policy design, DOM2 enhances policy expressiveness and diversity based on diffusion model. Specifically, we incorporate a diffusion model into the policy network and propose a trajectory-based data-reweighting scheme in training. These key ingredients significantly improve algorithm robustness against environment changes and achieve significant improvements in performance, generalization and data-efficiency. Our extensive experimental results demonstrate that DOM2 outperforms existing state-of-the-art methods in all multi-agent particle and multi-agent MuJoCo environments, and generalizes significantly better to shifted environments {(in $28$ out of $30$ settings evaluated)} thanks to its high expressiveness and diversity. Moreover, DOM2 is ultra data efficient and requires no more than $5\%$ data for achieving the same performance compared to existing algorithms (a $20\times$ improvement in data efficiency).
---

Title: Offline Diffusion Policy for Multi-User Delay-Constrained Scheduling
Link: https://arxiv.org/abs/2501.12942
Tags: arxiv, csai
Abstract/Content: arXiv:2501.12942v2 Announce Type: replace Abstract: Effective multi-user delay-constrained scheduling is crucial in various real-world applications, including embodied AI, instant messaging, live streaming, and data center management, where efficient resource allocation is required among users with diverse delay sensitivities. In these scenarios, schedulers must make real-time decisions to satisfy both delay and resource constraints without prior knowledge of system dynamics, which are often time-varying and challenging to estimate. {Current learning-based methods typically require online interactions with actual systems during the training stage. Therefore, these approaches are often difficult or impractical, as they can significantly degrade system performance and incur substantial service costs.} To address these challenges, we propose a novel offline reinforcement learning-based algorithm, named \underline{S}cheduling By \underline{O}ffline Learning with \underline{C}ritic Guidance and \underline{D}iffusion Model (SOCD), to learn efficient scheduling policies purely from pre-collected \emph{offline data}. SOCD innovatively employs a diffusion policy, complemented by a sampling-free critic network for policy guidance. By integrating the Lagrangian multiplier optimization into the offline reinforcement learning, SOCD efficiently trains high-quality constraint-aware policies exclusively from available datasets, eliminating the need for online interactions with the system. Experimental results demonstrate that SOCD is resilient to various system dynamics, including partially observable and large-scale environments, and delivers superior performance compared to existing methods.
---

Title: FOCUS on Contamination: Hydrology-Informed Noise-Aware Learning for Geospatial PFAS Mapping
Link: https://arxiv.org/abs/2502.14894
Tags: arxiv, csai
Abstract/Content: arXiv:2502.14894v5 Announce Type: replace-cross Abstract: Per- and polyfluoroalkyl substances (PFAS) are persistent environmental contaminants with significant public health impacts, yet large-scale monitoring remains severely limited due to the high cost and logistical challenges of field sampling. The lack of samples leads to difficulty simulating their spread with physical models and limited scientific understanding of PFAS transport in surface waters. Yet, rich geospatial and satellite-derived data describing land cover, hydrology, and industrial activity are widely available. We introduce FOCUS, a geospatial deep learning framework for PFAS contamination mapping that integrates sparse PFAS observations with large-scale environmental context, including priors derived from hydrological connectivity, land cover, source proximity, and sampling distance. These priors are integrated into a principled, noise-aware loss, yielding a robust training objective under sparse labels. Across extensive ablations, robustness analyses, and real-world validation, FOCUS consistently outperforms baselines including sparse segmentation, Kriging, and pollutant transport simulations, while preserving spatial coherence and scalability over large regions. Our results demonstrate how AI can support environmental science by providing screening-level risk maps that prioritize follow-up sampling and help connect potential sources to surface-water contamination patterns in the absence of complete physical models.
---

Title: Position: Stop Anthropomorphizing Intermediate Tokens as Reasoning/Thinking Traces!
Link: https://arxiv.org/abs/2504.09762
Tags: arxiv, csai
Abstract/Content: arXiv:2504.09762v4 Announce Type: replace Abstract: Intermediate token generation (ITG), where a model produces output before the solution, has become a standard method to improve the performance of language models on reasoning tasks. These intermediate tokens have been called \say{reasoning traces} or even \say{thinking traces} -- implicitly anthropomorphizing the traces, and implying that these traces resemble steps a human might take when solving a challenging problem, and as such can provide an interpretable window into the operation of the model's thinking process to the end user. In this position paper, we present evidence that this anthropomorphization isn't a harmless metaphor, and instead is quite dangerous -- it confuses the nature of these models and how to use them effectively, and leads to questionable research. We call on the community to avoid such anthropomorphization of intermediate tokens.
---

Title: Erased but Not Forgotten: How Backdoors Compromise Concept Erasure
Link: https://arxiv.org/abs/2504.21072
Tags: arxiv, csai
Abstract/Content: arXiv:2504.21072v3 Announce Type: replace-cross Abstract: The expansion of text-to-image diffusion models has raised concerns about harmful outputs, from fabricated depictions of public figures to sexually explicit imagery. To mitigate such risks, prior work has proposed concept erasure methods that aim to sever unwanted concepts from the model via fine-tuning, yet it remains unclear whether these approaches truly remove all links to the harmful concept or merely conceal superficial connections. In this work, we reveal a critical vulnerability, the Erasure Evasion Backdoor (EEB): an adversary binds a backdoor trigger to a concept slated for removal, and this malicious link survives subsequent erasure. We show that both black-box and white-box adversaries can instantiate this threat. Across six state-of-the-art erasure methods, including robust ones that explicitly search for alternative representations of the target concept, EEB consistently exposes harmful content: up to 82% success against celebrity-identity unlearning, up to 94% for object erasure, and up to 16 times amplification of explicit-content exposure. While EEB uncovers a blind spot in current erasure methods, it also provides a diagnostic tool for stress-testing future concept erasure techniques.
---

Title: The Unreasonable Effectiveness of Discrete-Time Gaussian Process Mixtures for Robot Policy Learning
Link: https://arxiv.org/abs/2505.03296
Tags: arxiv, csai
Abstract/Content: arXiv:2505.03296v2 Announce Type: replace-cross Abstract: We present Mixture of Discrete-time Gaussian Processes (MiDiGap), a novel approach for flexible policy representation and imitation learning in robot manipulation. MiDiGap enables learning from as few as five demonstrations using only camera observations and generalizes across a wide range of challenging tasks. It excels at long-horizon behaviors such as making coffee, highly constrained motions such as opening doors, dynamic actions such as scooping with a spatula, and multimodal tasks such as hanging a mug. MiDiGap learns these tasks on a CPU in less than a minute and scales linearly to large datasets. We also develop a rich suite of tools for inference-time steering using evidence such as collision signals and robot kinematic constraints. This steering enables novel generalization capabilities, including obstacle avoidance and cross-embodiment policy transfer. MiDiGap achieves state-of-the-art performance on diverse few-shot manipulation benchmarks. On constrained RLBench tasks, it improves policy success by 76 percentage points and reduces trajectory cost by 67%. On multimodal tasks, it improves policy success by 48 percentage points and increases sample efficiency by a factor of 20. In cross-embodiment transfer, it more than doubles policy success. We make the code publicly available at https://midigap.cs.uni-freiburg.de.
---

Title: A Physics-Inspired Optimizer: Velocity Regularized Adam
Link: https://arxiv.org/abs/2505.13196
Tags: arxiv, csai
Abstract/Content: arXiv:2505.13196v3 Announce Type: replace-cross Abstract: We introduce Velocity-Regularized Adam (VRAdam), a physics-inspired optimizer for training deep neural networks that draws on ideas from quartic terms for kinetic energy with its stabilizing effects on various system dynamics. Previous algorithms, including the ubiquitous Adam, operate at the so-called adaptive edge of stability regime during training, leading to rapid oscillations and slowed convergence of loss. However, VRAdam adds a higher order penalty on the learning rate based on the velocity such that the algorithm automatically slows down whenever weight updates become large. In practice, we observe that the effective dynamic learning rate shrinks in high-velocity regimes, and damping oscillations. By combining this velocity-based regularizer for global damping with per-parameter scaling of Adam, we create a powerful hybrid optimizer. For this optimizer, we provide rigorous theoretical analysis of operation at the edge of stability from a physical and control perspective for the momentum. Furthermore, we derive convergence bounds with the rate $\mathcal{O}(\ln(N)/\sqrt{N})$ for a stochastic non convex objective under mild assumptions. We demonstrate that VRAdam exceeds the performance against standard optimizers including AdamW. We benchmark various tasks such as image classification, language modeling, and generative modeling using diverse architectures and training methodologies including Convolutional Neural Networks (CNNs), Transformers, and GFlowNets.
---

Title: Pass@K Policy Optimization: Solving Harder Reinforcement Learning Problems
Link: https://arxiv.org/abs/2505.15201
Tags: arxiv, csai
Abstract/Content: arXiv:2505.15201v5 Announce Type: replace-cross Abstract: Reinforcement Learning (RL) algorithms sample multiple n>1 solution attempts for each problem and reward them independently. This optimizes for pass@1 performance and prioritizes the strength of isolated samples at the expense of the diversity and collective utility of sets of samples. This under-utilizes the sampling capacity, limiting exploration and eventual improvement on harder examples. As a fix, we propose Pass-at-k Policy Optimization (PKPO), a transformation on the final rewards which leads to direct optimization of pass@k performance, thus optimizing for sets of samples that maximize reward when considered jointly. Our contribution is to derive novel low variance unbiased estimators for pass@k and its gradient, in both the binary and continuous reward settings. We show optimization with our estimators reduces to standard RL with rewards that have been jointly transformed by a stable and efficient transformation function. While previous efforts are restricted to k=n, ours is the first to enable robust optimization of pass@k for any arbitrary k <= n. Moreover, instead of trading off pass@1 performance for pass@k gains, our method allows annealing k during training, optimizing both metrics and often achieving strong pass@1 numbers alongside significant pass@k gains. We validate our reward transformations on toy experiments, which reveal the variance reducing properties of our formulations. We also include real-world examples using the open-source LLM, GEMMA-2. We find that our transformation effectively optimizes for the target k. Furthermore, higher k values enable solving more and harder problems, while annealing k boosts both the pass@1 and pass@k . Crucially, for challenging task sets where conventional pass@1 optimization stalls, our pass@k approach unblocks learning, likely due to better exploration by prioritizing joint utility over the utility of individual samples.
---

Title: \texttt{Range-Arithmetic}: Verifiable Deep Learning Inference on an Untrusted Party
Link: https://arxiv.org/abs/2505.17623
Tags: arxiv, csai
Abstract/Content: arXiv:2505.17623v2 Announce Type: replace-cross Abstract: Verifiable computing (VC) has gained prominence in decentralized machine learning systems, where resource-intensive tasks like deep neural network (DNN) inference are offloaded to external participants due to blockchain limitations. This creates a need to verify the correctness of outsourced computations without re-execution. We propose \texttt{Range-Arithmetic}, a novel framework for efficient and verifiable DNN inference that transforms non-arithmetic operations, such as rounding after fixed-point matrix multiplication and ReLU, into arithmetic steps verifiable using sum-check protocols and concatenated range proofs. Our approach avoids the complexity of Boolean encoding, high-degree polynomials, and large lookup tables while remaining compatible with finite-field-based proof systems. Experimental results show that our method not only matches the performance of existing approaches, but also reduces the computational cost of verifying the results, the computational effort required from the untrusted party performing the DNN inference, and the communication overhead between the two sides.
---


** Raw LLM Output
* cs.DB (Databases)
** 🧐 Обзор
В последние сутки наблюдается сильный тренд на интеграцию больших языковых моделей с управляемыми данными, особенно в корпоративных средах и для аудита знаний. Параллельно развиваются специализированные индексы для временных рядов и векторного поиска, обеспечивающие точность и скорость на распределенных данных. Также заметно внимание к формализации языков запросов для графовых баз данных и нейросетевых вычислений поверх реляционных структур.

** 🛠 Практика и Системы
- [[https://arxiv.org/abs/2604.21413][RUBICON: Agentic AI for Messy Enterprise Data]]
:WHAT: Система агентов ИИ с таблично-ориентированной архитектурой и ограниченным интерфейсом запросов для enterprise-данных.
:IMPACT: Достигает 100% точности на сложных запросах к разнородным источникам, значительно снижая затраты токенов и задержку по сравнению с базовыми LLM-агентами.
- [[https://arxiv.org/abs/2606.09824][TSseek: Regular Expression-Based Similarity Search for Distributed Time Series Datasets]]
:WHAT: Фреймворк поиска похожих временных рядов на основе регулярных выражений и распределенного пространственного индекса.
:IMPACT: Позволяет искать паттерны и тренды вместо точных последовательностей, обеспечивая точные ответы быстрее существующих аналогов для подпоследовательностей.
- [[https://arxiv.org/abs/2606.01183][The World's Fastest Matching Engine Algorithm]]
:WHAT: Алгоритм и структуры данных (Priority-Indicated Node) для сопоставления ордеров в трейдинге с суб-микросекундной задержкой.
:IMPACT: Увеличивает пропускную способность в 4.7-11 раз по сравнению с open-source решениями, устраняя латентность хвостовых задержек при микро-всплесках.

** 🕸 Графы и Алгоритмы
- [[https://arxiv.org/abs/2604.11454][Foundations of the GraphAlg Language]]
:ALGO: Формальное обоснование предметно-ориентированного языка GraphAlg на основе расширений MATLANG для манипуляции матрицами.
:IMPACT: Позволяет пользователям определять алгоритмы непосредственно в графовых базах данных с гарантиями симуляции через индукцию.
- [[https://arxiv.org/abs/2606.11582][Querying Cohesive Subgraph regarding Span-Constrained Triangles on Temporal Graphs with Dynamic Index Maintenance]]
:ALGO: Индексы для запросов $(k,\delta)$-truss на временных графах с поддержкой динамического обновления.
:IMPACT: Сжимает хранение всех трассов до $10^{-4}$ и ускоряет запросы на 2-4 порядка по сравнению с подходами без индексов.
- [[https://arxiv.org/abs/2606.11946][Neuro-Relational Programs: Unifying Queries and Neural Computation over Structured Data]]
:ALGO: Декларативный язык запросов (NRPs), объединяющий реляционную логику и нейронные вычисления (вложения) в единой формальной системе.
:IMPACT: Обобщает GNN и запросы к базам данных, обеспечивая точную связь с логикой первого порядка и весовыми структурами.

** 📄 Остальное
- [[https://arxiv.org/abs/2603.24080][LLMpedia: A Transparent Framework to Materialize an LLM's Encyclopedic Knowledge at Scale]] — Аудит фактологической точности LLM путем материализации статей и сравнения с Wikipedia, выявляющий проблемы верифицируемости.
- [[https://arxiv.org/abs/2606.11789][Efficient Graph Indexing for Interval-Aware Vector Search]] — Унифицированный графовый индекс URNG для поиска ближайших соседей с учетом интервальных ограничений.
- [[https://arxiv.org/abs/2606.11235][Few-Shot Resampling for Scalable Statistically-Sound Data Mining]] — Метод FewRS для оценки статистической значимости результатов майнинга данных с уменьшением времени вычислений до двух порядков.
- [[https://arxiv.org/abs/2605.02030][U-HNSW: An Efficient Graph-based Solution to ANNS Under Universal Lp Metrics]] — Первый графовый метод для приближенного поиска ближайших соседей под универсальными метриками $L_p$.
- [[https://arxiv.org/abs/2606.11760][A Fast Gaussian Mechanism under Continual Observation, with Applications]] — Структура данных для выборки шума за константное время в задачах дифференциальной приватности при непрерывном наблюдении.

* cs.DC (Distributed Computing)
** 🧐 Обзор
Исследования сосредоточены на оптимизации инфраструктуры для ИИ, включая компиляцию тензорных программ и эффективное умножение матриц на разнородном железе. Важное внимание уделяется энергопотреблению при инференсе, распределенным протоколам согласования в динамических сетях и блокчейн-системам с полезной работой.

** 🛠 Практика и Системы
- [[https://arxiv.org/abs/2512.22219][MPK: A Compiler and Runtime for Mega-Kernelizing Tensor Programs]]
:WHAT: Компилятор и рантайм для трансформации инференса много-GPU моделей в единый мега-кернел с планированием на уровне SM.
:IMPACT: Снижает задержку инференса LLM до 1.7 раз, обеспечивая слияние ядер и перекрытие вычислений с коммуникацией.
- [[https://arxiv.org/abs/2605.06057][FalconGEMM: Surpassing Hardware Peaks with Lower-Complexity Matrix Multiplication]]
:WHAT: Кросс-платформенный фреймворк для автоматического развертывания алгоритмов умножения матриц низкой сложности.
:IMPACT: Превышает пиковую производительность стандартных библиотек (cuBLAS, MKL) на 7-17% на задачах обучения и инференса LLM.
- [[https://arxiv.org/abs/2509.20241][Energy Use of AI Inference, Efficiency Pathways, and Test-Time Scaling]]
:WHAT: Bottom-up фреймворк для оценки энергопотребления инференса ИИ на масштабных развертываниях.
:IMPACT: Показывает, что общественные оценки завышены в 4-20 раз, и предлагает пути снижения энергозатрат дата-центров.

** 🕸 Графы и Алгоритмы
- [[https://arxiv.org/abs/2209.03999][Consensus on Dynamic Stochastic Block Models: Fast Convergence and Phase Transitions]]
:ALGO: Модели консенсуса по правилу большинства на эволюционирующих стохастических блочных моделях (SBM).
:IMPACT: Доказывает быструю сходимость и фазовые переходы в сетях с динамической структурой сообществ, что важно для распределенных систем.

** 📄 Остальное
- [[https://arxiv.org/abs/2512.13666][SEDULity: A Proof-of-Learning Framework for Distributed and Secure Blockchains with Efficient Useful Work]] — Блокчейн-система Proof-of-Learning, использующая обучение ML моделей как полезную работу вместо майнинга.
- [[https://arxiv.org/abs/2605.05727][LLM-Enhanced Deep Reinforcement Learning for Task Offloading in Collaborative Edge Computing]] — Гибридный фреймворк LeDRL для оффлоадинга задач на edge-устройствах, сочетающий轻量кий LLM и DRL.
- [[https://arxiv.org/abs/2506.18401][Impossibility Results for Strong Linearizability: The Difficulty of Consistent Refereeing]] — Теоретические результаты о невозможности сильной линеаризуемости для некоторых конкурентных объектов без полного консенсуса.
- [[https://arxiv.org/abs/2603.09738][Ensuring Data Freshness in Multi-Rate Task Chains Scheduling]] — Планирование задач с ограничениями на свежесть данных для безопасных автономных систем.

* cs.AI (Artificial Intelligence)
** 🧐 Обзор
Акцент смещается на верифицируемый инференс и эффективное обучение политик без онлайн-взаимодействия в системах планирования. Также обсуждаются вопросы безопасности моделей, концептуального забвения и интерпретируемости промежуточных вычислений в контексте системного использования.

** 🛠 Практика и Системы
- [[https://arxiv.org/abs/2505.17623][\texttt{Range-Arithmetic}: Verifiable Deep Learning Inference on an Untrusted Party]]
:WHAT: Фреймворк для верифицируемого инференса DNN, трансформирующий неарифметические операции в верифицируемые шаги.
:IMPACT: Снижает вычислительные затраты и накладные расходы на связь при проверке корректности outsourced вычислений в децентрализованных системах.
- [[https://arxiv.org/abs/2501.12942][Offline Diffusion Policy for Multi-User Delay-Constrained Scheduling]]
:WHAT: Алгоритм SOCD для обучения политик планирования с ограничениями задержки исключительно на офлайн-данных.
:IMPACT: Позволяет оптимизировать распределение ресурсов без онлайн-взаимодействия с системой, что критично для дорогих или рискованных сред.

** 📄 Остальное
- [[https://arxiv.org/abs/2606.11437][The Power of Test-Time Training for Approximate Sampling]] — Формализация тест-временного обучения (TTT) как задачи сэмплирования, показывающая оптимальность подходов случайного блуждания.
- [[https://arxiv.org/abs/2505.13196][A Physics-Inspired Optimizer: Velocity Regularized Adam]] — Оптимизатор VRAdam, использующий регуляризацию скорости для стабилизации обучения глубоких сетей.
- [[https://arxiv.org/abs/2504.21072][Erased but Not Forgotten: How Backdoors Compromise Concept Erasure]] — Исследование уязвимостей методов удаления концептов из диффузионных моделей через бэкдоры.
- [[https://arxiv.org/abs/2504.09762][Position: Stop Anthropomorphizing Intermediate Tokens as Reasoning/Thinking Traces!]] — Позиционная статья против антропоморфизации промежуточных токенов LLM как следов мышления.

* physics.soc-ph (Social Physics & Networks)
** 🧐 Обзор
Анализ сетей расширяется за счет учета взаимодействий высшего порядка (гиперграфы) и перколяционных моделей для городских структур. Исследуется влияние сетевой динамики на коллективные решения, распространение эпидемий и поляризацию в социальных медиа.

** 🕸 Графы и Алгоритмы
- [[https://arxiv.org/abs/2511.13452][Collective decision-making with higher-order interactions on $d$-uniform hypergraphs]]
:ALGO: Модель динамики мнений на $d$-uniform гиперграфах с учетом групповых взаимодействий и качества опций.
:IMPACT: Выявляет критические пороги стабильности консенсуса, независимые от топологии, но зависимые от размера групп взаимодействия.
- [[https://arxiv.org/abs/2606.12399][Revealing Peri-Urban Dislocation through Percolation Analysis]]
:ALGO: Применение перколяционного анализа уличных сетей для выявления структурной дислокации пригородных зон.
:IMPACT: Предлагает новый метрический инструмент для диагностики иерархических несоответствий в urban-системах помимо традиционных метрик плотности.

** 📄 Остальное
- [[https://arxiv.org/abs/2606.12013][Emergent dilemma and periodic oscillation in the nonlinear interplay between epidemic and behavior]] — Модель коэволюции эпидемии и поведения, показывающая парадоксальный отказ от мер защиты при высокой заразности.
- [[https://arxiv.org/abs/2502.05255][Incivility in Public Health Policy Discussions Spills Over to Public Engagement with Climate Issues]] — Анализ перетока аффективной поляризации и нецивильности между обсуждениями здоровья и климата в соцсетях.
- [[https://arxiv.org/abs/2606.08972][Three-dimensional Fundamental Diagrams of Five-neighbor Particle Cellular Automata]] — Исследование фундаментальных диаграмм в клеточных автоматах с сохранением второй плотности.

* cs.DS (Data Structures & Algorithms)
** 🧐 Обзор
Теоретические работы касаются приватности данных и сложности запросов, предлагая алгоритмы с гарантиями для синтетических данных и линейного программирования. Результаты имеют потенциал для применения в системах управления данными с ограничениями приватности.

** 📄 Остальное
- [[https://arxiv.org/abs/2606.11283][Fixed-Parameter Tractability of Private Synthetic Data Generation]] — Доказательство FPT для генерации синтетических данных с дифференциальной приватностью на основе ширины дерева графа инцидентности.
- [[https://arxiv.org/abs/2606.11820][On finding exact solutions of linear programs in the oracle model]] — Алгоритм нахождения точных решений линейных программ в модели оракула с полиномиальным временем для рациональных данных.
- [[https://arxiv.org/abs/2210.09899][First Order Logic on Pathwidth Revisited Again]] — Улучшение зависимости сложности теоремы Куркелля для логики первого порядка на графах ограниченной путевой ширины.

* TODO [2026-07-01 09:34:13] [llm] [ERROR] FAIL
DEADLINE: <2026-07-01 Wed 09:34>
:PROPERTIES:
:CREATED: [2026-07-01 09:34:13]
:END:
Error: Callback error: Invalid use of ‘\’ in replacement text

** Input
You are a Research Assistant monitoring arXiv preprints.
Target Audience: Graph & Data Systems Researcher.
Language: Russian.
Output Format: Org-mode.

Context:
Focus on Databases, Distributed Systems, Graph Algorithms, Network Analysis, and applied ML for systems.

CRITICAL OUTPUT RULES:
- Return ONLY raw Org-mode text.
- Do NOT use markdown, code fences, XML/JSON wrappers, or any commentary.
- Start directly with the first Org heading.
- Follow Org heading syntax strictly.

Task:
1. Group papers by arXiv categories: cs.DB (Databases), cs.AI (Artificial Intelligence), physics.soc-ph (Social Physics & Networks), cs.DS (Data Structures & Algorithms), cs.DC (Distributed Computing).
2. For each non-empty category, generate the following structure:

* <Category Name>
** 🧐 Обзор
2-4 sentences on trend for the last 1 days: what is new, what is maturing, what is practically relevant.

** 🛠 Практика и Системы
- [[<Link>][<Title>]]
:WHAT: What system/optimization/method is introduced.
:IMPACT: Why it matters in practice.

** 🕸 Графы и Алгоритмы
- [[<Link>][<Title>]]
:ALGO: Key algorithmic or modeling contribution.
:IMPACT: Why it matters for graph/data systems.

** 📄 Остальное
- [[<Link>][<Title>]] — one concise sentence.

Selection constraints:
- Prioritize papers with clear system impact or strong algorithmic contribution.
- Deprioritize purely theoretical work unless it has plausible practical/system relevance.
- Omit empty subsections if no papers match.
- Omit empty categories.

Data:
Title: Higher-order modeling of face-to-face interactions
Link: https://arxiv.org/abs/2406.05026
Tags: arxiv, socph
Abstract/Content: arXiv:2406.05026v2 Announce Type: replace Abstract: The most fundamental social interactions among humans occur face-to-face. Their features have been extensively studied in recent years, owing to the availability of high-resolution data on individuals' proximity. Mathematical models based on mobile agents have been crucial to understanding the spatio-temporal organization of face-to-face interactions. However, these models focus on dyadic relationships only, failing to characterize interactions in larger groups of individuals. Here, we propose a model in which agents interact with each other by forming groups of different sizes. Each group has a degree of social attractiveness, based on which neighboring agents decide whether to join. Our framework reproduces different properties of groups in face-to-face interactions, including their distribution, the correlation in their number, and their persistence in time, which dyadic models cannot replicate. Furthermore, it captures homophilic patterns at the level of higher-order interactions, going beyond standard pairwise approaches. Our work provides further evidence that higher-order interactions are key to describe human face-to-face contacts, paving the way for further investigation of how group dynamics at a microscopic scale affects social phenomena at a macroscopic scale.
---

Title: Generating consensus and dissent on massive discussion platforms with a semantic-vector model
Link: https://arxiv.org/abs/2601.13932
Tags: arxiv, socph
Abstract/Content: arXiv:2601.13932v2 Announce Type: replace Abstract: Reaching consensus on massive discussion networks is critical for reducing noise and achieving optimal collective outcomes. However, the natural tendency of humans to preserve their initial ideas constrains the emergence of global solutions. To address this, Collective Intelligence (CI) platforms facilitate the discovery of globally superior solutions. We introduce a dynamical system based on the standard $O(N)$ model to drive the aggregation of semantically similar ideas. The system consists of users represented as nodes in a $d=2$ lattice with nearest-neighbor interactions, where their ideas are represented by semantic vectors computed with a pretrained embedding model. We analyze the system's equilibrium states as a function of the coupling parameter $\beta$. Our results show that $\beta > 0$ drives the system toward a ferromagnetic-like phase (global consensus), while $\beta < 0$ induces an antiferromagnetic-like state (maximum dissent), where users maximize semantic distance from their neighbors. This framework offers a controllable method for managing the tradeoff between cohesion and diversity in CI platforms.
---

Title: A dynamic mechanism for prevalence of triangles in competitive networks
Link: https://arxiv.org/abs/2603.17584
Tags: arxiv, socph
Abstract/Content: arXiv:2603.17584v2 Announce Type: replace Abstract: Triangles are abundant in real-world networks but rare in standard null models for sparse graphs. Existing explanations typically rely on explicit triadic closure mechanisms or geometry-based connection rules. We propose an alternative hypothesis: the frequent appearance of triangles may arise naturally from the requirement of dynamic stability that maintains coexistence of species in Lotka-Volterra systems with equal competitive interactions. To evaluate this idea, we prove that, across all possible interaction graphs, coexistence is guaranteed whenever the coupling strength is below the reciprocal of the graph's maximum degree, and guaranteed not to occur when the coupling strength exceeds 1. This leaves a large gap that is unexplained by the graph degrees alone. We notice that the lower and upper bounds are achieved for star and complete graphs respectively and to investigate further what structural properties of the interaction graph control the critical coupling within the gap, we optimise networks algorithmically while keeping the degree sequence fixed. We find that networks supporting stronger interaction strengths consistently exhibit higher clustering coefficients in several network models. Moreover, in real-world grassland plant networks, we observe higher clustering and stronger stability than those expected from a configuration model with the same degree sequence. Our result suggests that triangles, and clustering in general, may emerge as a structural signature of stabilising competition.
---

Title: Scale-free congestion clusters in large-scale traffic networks: a continuum modeling study
Link: https://arxiv.org/abs/2604.05439
Tags: arxiv, socph
Abstract/Content: arXiv:2604.05439v2 Announce Type: replace Abstract: Recent empirical studies have reported that spatiotemporal congestion clusters in urban traffic exhibit scale-free statistics, with cluster size following a power-law distribution. In this study, we address whether macroscopic continuum descriptions of traffic flow are capable of generating such scale-free spatiotemporal congestion patterns. To this end, we analyze the second-order Aw-Rascle-Zhang model on directed networks under junction coupling. The governing equations are solved by a high-order discontinuous Galerkin scheme, and junction fluxes are determined by an optimization-based coupling procedure enforcing conservation and admissibility at intersections. Congestion is defined by thresholding the road-averaged density, and spatiotemporal clusters are extracted as connected components in space and time. Numerical experiments on lattice networks of varying sizes reveal that the cluster size follows a robust power-law distribution. Moreover, when rescaled by the linear system size inherent to the two-dimensional network geometry, the distribution collapses onto an approximately universal curve, indicating finite-size scaling governed by the linear system size. The observed power-law statistics and finite-size scaling are reminiscent of scale-invariant dynamics characteristic of self-organized criticality. These results demonstrate that macroscopic continuum traffic models can reproduce large-scale statistical features observed in real urban congestion dynamics.
---

Title: Role of volatility mixing in wealth condensation transition
Link: https://arxiv.org/abs/2604.13885
Tags: arxiv, socph
Abstract/Content: arXiv:2604.13885v3 Announce Type: replace-cross Abstract: We study the role of heterogeneous volatility in a networked wealth dynamics model and its impact on the wealth condensation transition. Extending the Bouchaud--M{\'e}zard framework, we introduce binary volatility in networks and investigate how its configuration affects the effective power-law tail exponent of the wealth distribution. Using a stochastic block model, we control the mixing between volatility groups and show that the effective exponent is governed not only by the global parameter $\Lambda=2J/\beta^2$ but also by the volatility configuration in the network. We find that local interactions between nodes with different volatility induce a neutralization of group-wise exponents, which lowers the aggregate tail exponent and can drive a condensation transition across $\gamma_{\rm c}=2$. Our results identify volatility mixing as another control mechanism for wealth condensation and highlight the importance of noise heterogeneity in nonequilibrium systems on networks.
---

Title: Cycle holonomy captures higher-order compatibility constraints in remote synchronization
Link: https://arxiv.org/abs/2604.19682
Tags: arxiv, socph
Abstract/Content: arXiv:2604.19682v2 Announce Type: replace Abstract: Higher-order interactions have typically been modeled using hypergraphs or simplicial complexes, where interactions explicitly involve more than two nodes. Here we demonstrate that effective higher-order dynamical constraints emerge naturally on ordinary graphs, provided the interaction carries nontrivial topological structure. We study a gauge-coupled phase model with edge phase lags whose accumulation around closed loops produces gauge-invariant mismatches. We show that the associated twisted Laplacian admits a zero mode if and only if all cycle holonomies vanish. Consequently, global compatibility is obstructed not by local pairwise mismatches, but by intrinsic topological frustration on cycles. We then connect this framework to the symmetric Sakaguchi--Kuramoto model, whose local coupling law differs from the gauge-coupled model but whose node phases impose cycle closure on physical phase differences. For cactus graphs, path mismatches induced by the symmetric lag can be represented through associated cycle holonomies, providing a static spectral encoding of their global residual incompatibility. Our results establish a spectral framework linking frustration to cycle-level constraints and identify cycle holonomy as a local-to-global diagnostic of path incompatibility in synchronization dynamics.
---

Title: Spin-Induced Non-Markovian Time-Crystal-Like Dynamics and Fractal Scaling in the Bateman Dual Oscillator
Link: https://arxiv.org/abs/2605.19917
Tags: arxiv, socph
Abstract/Content: arXiv:2605.19917v2 Announce Type: replace-cross Abstract: Can a closed quantum system generate persistent time-crystal-like dynamics without external driving? Within the Bateman dual oscillator framework, we show that the answer is affirmative. We consider a nonrelativistic (2+1)-dimensional system in which spin-induced spatial deformation generates an effective Bateman oscillator structure. After quantization, the system is governed by a time-independent Hermitian Hamiltonian describing coherent coupling between damped and amplified oscillator sectors while preserving the total energy of the global doubled system. Tracing over the amplified sector, we derive an effective non-Markovian reduced dynamics for the observable subsystem. The resulting memory effects sustain persistent oscillations of subsystem observables and generate emergent time-crystal-like temporal ordering without external periodic driving or equilibrium spontaneous symmetry breaking. Since the oscillatory behavior originates from nonequilibrium reduced subsystem dynamics rather than equilibrium expectation values of the full Hamiltonian, the mechanism lies outside the assumptions of conventional no-go theorems for equilibrium time crystals. The same dynamics further exhibits logarithmic-spiral trajectories and self-similar fractal scaling, revealing a direct connection between coherent dissipative dynamics, non-Markovian memory effects, and emergent temporal ordering in a globally unitary quantum system. In this specific sense, "watching the growth" of these self-similar structures corresponds to observing the gradual formation of time-crystal-like ordering.
---

Title: Match classification in the last round of four-team round-robin tournaments
Link: https://arxiv.org/abs/2605.25610
Tags: arxiv, socph
Abstract/Content: arXiv:2605.25610v2 Announce Type: replace Abstract: Classification of matches played in the last rounds of sports competitions is a well-established tool for evaluating tournament designs. Both deterministic and probabilistic approaches are available for this purpose. Our paper offers the first comparison of them by analysing the most prominent example of four-team round-robin competitions, the group stage of the FIFA World Cup. We show that both methods are highly relevant in practice: all (four) deterministic and (six) probabilistic match types occurred in the 2014 and 2018 FIFA World Cups, respectively. The probabilistic model, which accounts for the relative benefits of attacking and defending, provides deeper insights; for instance, the competitive matches from the deterministic approach can be of any of the six probabilistic types. Finally, the probabilistic framework is used to quantify and decompose the impact of the main reforms introduced for the 2026 FIFA World Cup: the expansion to 48 teams, as well as the modified qualification and tie-breaking rules.
---

Title: Can homophily explain public underestimation of climate policy support?
Link: https://arxiv.org/abs/2606.15106
Tags: arxiv, socph
Abstract/Content: arXiv:2606.15106v2 Announce Type: replace Abstract: Many climate change mitigation policies enjoy large majority support from the U.S. public. Yet, both Republicans and Democrats underestimate public support for climate policies, on average, with Republicans underestimating by more. Explaining this is a major puzzle in climate change politics. Homophily is one possible explanation: if citizens are selectively exposed to views reinforcing their own, then policy opponents might underestimate support more than supporters. Here, we explore how homophily could interact with social network structure to produce misperceptions of policy support, using a stochastic block model and preferential attachment model. Homophily alone can explain opponents underestimating support by more than supporters, but supporters only underestimate support when their homophily is so low that they disproportionately associate with opponents. We then expand our model to combine homophily with Bayesian rescaling, inaccurate priors, or asymmetric prominence of opposing opinions (simulating media bias). With Bayesian rescaling and inaccurate priors, homophily would still need to be highly asymmetric to produce realistic misperception patterns. Media bias combined with realistic, symmetric homophily can produce realistic misperception patterns in our model. However, empirical evidence on media bias in coverage of climate change policy is mixed. Our analyses provide theoretical foundations for advancing understanding of public opinion misperception, on climate change and other issues.
---

Title: Cascading Impacts of the USA--China Trade War on Global Oilseed Supply Chain
Link: https://arxiv.org/abs/2606.30685
Tags: arxiv, socph
Abstract/Content: arXiv:2606.30685v1 Announce Type: cross Abstract: Global supply chains are highly interconnected, making them vulnerable to cascading disruptions induced by trade policy shocks. Understanding how such disruptions propagate through production networks, and how mitigation mechanisms such as trade reallocation and production adjustment can alleviate their impacts, remains a central challenge. In this work, we develop a linear programming formulation of an Input-Output (IO) system that captures cascading supply-chain disruptions together with trade reallocation and production expansion. Our formulation yields a system-level equilibrium characterization that enables the joint analysis of disruption propagation and mitigation within a unified framework. We propose an efficient algorithm for computing approximate equilibrium solutions by minimizing total unmet demand in large IO systems. We apply our approach to tariff-induced disruptions in the global oilseeds supply chain arising from the U.S.-China trade war. Our results show that a localized 70% disruption to flows from the U.S. oilseeds sector to China leads to a 3.27% loss in global output, with China experiencing a disproportionate loss of 14.02%. As a counterfactual mitigation strategy, allowing a 20% reallocation from Brazil's oilseed sector to China significantly reduces global output losses to 1.36%, although pressure remains high on final-demand flows. We further investigate production expansion as an additional mitigation mechanism and show that it introduces tradeoffs between reducing global final-demand losses and protecting Brazil's domestic flows. Domestic reallocation disproportionately shifts losses toward smaller economies, while globally sourced expansion redistributes losses more broadly across the network.
---

Title: Privacy-Preserving Federated Averaging with Byzantine Aggregators in Asynchronous Networks
Link: https://arxiv.org/abs/2601.04930
Tags: arxiv, csdc
Abstract/Content: arXiv:2601.04930v2 Announce Type: replace Abstract: Federated Learning requires secure aggregation to prevent gradient leakage, yet existing protocols suffer from key limitations: they assume synchrony, require heavy peer-to-peer coordination, and do not tolerate aggregators that halt or omit messages. These constraints make current secure aggregation schemes impractical in large-scale, unreliable distributed settings.To overcome these limitations, we introduce a new secure aggregation protocol that operates in fully asynchronous networks, where messages may be arbitrarily delayed, and tolerates fully Byzantine aggregators that are capable of arbitrary deviations including premature halting. Our design combines several key mechanisms: clustering clients under verifiable coordinators, lightweight LWE-based masking (with masking components distributed across aggregators), and differential privacy applied to both intermediary and final aggregated models. We further propose verifiable shuffling of clients across clusters, which prevents any client from being systematically excluded by a Byzantine coordinator, and a fair inclusion mechanism that ensures the inclusion of straggling clients whose messages are late. The protocol eliminates all client-to-client communication, and its communication overhead scales only with the number of aggregators. It also ensures equal representation of clients across rounds, avoiding bias and preventing unbalanced privacy risks among clients. Overall, our protocol provides the first secure aggregation primitive that is both privacy-preserving and robust to fully Byzantine behavior in asynchronous networks, closing the gap between prior secure aggregation assumptions and real-world distributed systems.
---

Title: GORGO: Online Tuning for Cross-Region Network-Aware LLM Serving
Link: https://arxiv.org/abs/2602.11688
Tags: arxiv, csdc
Abstract/Content: arXiv:2602.11688v2 Announce Type: replace-cross Abstract: Increasingly, LLM inference services proxy client requests to engine replicas distributed globally. Load-balancing policies must jointly account for factors including KV-cache locality, replica load, and variable network latency when optimizing for metrics like latency and TTFT. However, existing systems only evaluate a subset of these factors in their cost model, leading to uneven concentrations of load and KV-cache across replicas. We present GORGO, a proxy architecture that holistically factors network latency, prefill cost, and queueing delay using tunable parameters. Since open-source chat datasets such as LMSYS-Chat1M and WildChat-4.8M lack long-context, high prefix-reuse data, we release a synthetic dataset, ART-Chat-2.5M, from long-context production metadata. On a tuning window from ART-Chat-2.5M, evolutionary strategies guide the GORGO policy's parameters to directly optimize p95 TTFT. During held-out evaluation windows, we fix the parameter values learned from tuning and improve p95 TTFT by 6.9-15.5% and p95 end-to-end (E2E) latency by 14.3-30.9% over baseline load-balancing policies such as simple session affinity and prefix-cache. The code and ART-Chat-2.5M dataset can be found at https://github.com/Arcadia-Research-Team/GORGO.
---

Title: Automated Byzantine-Resilient Clustered Decentralized Federated Learning for Battery Intelligence in Connected EVs
Link: https://arxiv.org/abs/2605.21115
Tags: arxiv, csdc
Abstract/Content: arXiv:2605.21115v3 Announce Type: replace Abstract: Federated learning (FL) has emerged as a promising paradigm for managing electric vehicle (EV) battery data in intelligent transportation systems (ITS), enabling privacy-preserving tasks such as anomaly detection and capacity estimation. However, most existing frameworks rely on centralized aggregation schemes, which pose critical limitations in terms of security and trust. To address these challenges, we propose ABC-DFL, an automated Byzantine-resilient clustered decentralized federated learning (C-DFL) framework for connected EVs. The proposed incentive-driven C-DFL system replaces the central server with an open-permissioned blockchain, featuring a new dynamic Quorum Byzantine Fault Tolerance (QBFT) protocol and an oracle-based aggregation layer, to enhance trust, security, and automation. At the core of ABC-DFL lies FLECA (Filtered Layered Enhanced Clustering Aggregation), a robust hierarchical aggregation protocol that mitigates Byzantine attacks by having each EV filter malicious updates using an adaptive threshold based on deviations from its reference model update. Oracle nodes, responsible for inter-group aggregation, employ robust clustering to isolate and aggregate model updates from trustworthy EV groups. Comprehensive experimental evaluations demonstrate that FLECA matches FedProx convergence under benign conditions and significantly outperforms existing defenses with attack impact scores below 0.10 in adaptive adversarial scenarios. Furthermore, several learning experiments with multitask models confirm the effectiveness and fairness of the incentive mechanism. Finally, on-chain and off-chain benchmarks validate the practicality of ABC-DFL.
---

Title: A Composable CRDT Layer for Byzantine-Resilient Deterministic Reconstruction
Link: https://arxiv.org/abs/2606.18966
Tags: arxiv, csdc
Abstract/Content: arXiv:2606.18966v3 Announce Type: replace Abstract: Conflict-free Replicated Data Types (CRDTs) ensure Strong Eventual Consistency without coordination, but typically assume benign participants and rely on validation or exclusion to handle Byzantine behavior. We address this problem through deterministic state reconstruction: rather than deciding which updates are admissible, all accepted updates are incorporated, while only a subset contributes to the reconstructed state. We instantiate this approach in Melda, a non-intrusive delta-state CRDT for JSON documents, and show that its reconstruction model guarantees convergence even under arbitrary update injection: adversarial updates are either structurally rejected or treated as inputs to the reconstruction process. We formalize this model and prove that replicas deriving state from the same set of updates cannot diverge despite equivocation, omission, or message reordering. We further show that authentication, authorization, and confidentiality can be layered without affecting convergence. Overall, this approach suggests that Byzantine tolerance can be achieved by decoupling update propagation from state derivation, allowing agreement on updates to be handled independently by external dissemination or consensus mechanisms.
---

Title: Decentralized Operations of Decarbonized Chemical Plants with Renewable-driven Transmission Systems
Link: https://arxiv.org/abs/2606.22973
Tags: arxiv, csdc
Abstract/Content: arXiv:2606.22973v3 Announce Type: replace Abstract: Electrification of ethane cracking offers a promising pathway to industrial decarbonization, provided that the electricity is sourced from renewable energy. However, integrating electrified chemical plant microgrids with a decarbonized power grid requires joint operations planning between Independent System Operators and chemical plants, which is hindered by the highly confidential nature of plant operational data. In this paper, we propose a privacy-friendly decentralized framework based on data isolation that jointly optimizes the Unit Commitment problem in the power system and microgrid scheduling in electrified ethane cracker plants. The framework employs the Alternating Direction Method of Multipliers, augmented with an auxiliary system-level penalty that accelerates convergence, allowing each subsystem to solve its local subproblem and share only minimal coordination signals. To reflect real-world conditions, numerical experiments are conducted on the ACTIVSg2000 test case, a synthetic model of the Texas transmission network, with 26 chemical plants identified from Texas mapped to their nearest grid connection points. In doing so, we characterize the cost of privacy-friendly decomposition on joint power and chemical system decisions, showing that data isolation results in consistently small optimality gaps, and that its emissions consequences are load-dependent and non-monotone.
---

Title: Hot AI in Cold Space: Thermal-Crosstalk-Aware Scheduling for Sustainable Orbital AI Clusters
Link: https://arxiv.org/abs/2606.26150
Tags: arxiv, csdc
Abstract/Content: arXiv:2606.26150v2 Announce Type: replace Abstract: Terrestrial AI training faces an unsustainable energy and water crisis, positioning Orbital Data Centers (ODCs) as a "zero operational carbon" alternative. However, the sub-$10\mu\text{s}$ communication latency required for synchronized scientific workloads, such as distributed Large Language Model (LLM) training, forces ODCs into extreme physical density, triggering a critical "Proximity-Thermal Paradox." As these high-density systems scale into Monolithic Structures or Proximity Swarms, they suffer from intense thermal-fluid crosstalk (heat traps in shared cooling loops) and thermal-radiative crosstalk (mutual heating that blocks deep-space cooling radiators). If left unmitigated, this persistent heat stagnation not only triggers severe thermal throttling that degrades training throughput, but also induces severe thermal fatigue, drastically shortening hardware lifespans and generating premature space e-waste. To make orbital AI truly sustainable, this position paper challenges traditional uniform load-sharing. We propose the Thermal-Aware Heterogeneity Thesis, which treats spatial cooling variances as a primary resource management dimension. Building on this, we introduce Thermal-Load Balancing (TLB), a software framework that dynamically migrates these intensive workloads to the coolest available units based on instantaneous fluid temperatures or absorbed radiation. Our analysis demonstrates that TLB resolves thermal bottlenecks to restore Model Flops Utilization (MFU), while simultaneously reducing physical thermal stress. Extending the operational lifespan of orbital hardware is crucial to amortize the massive embodied carbon of rocket launches, outlining a necessary pathway to scale orbital AI without accelerating e-waste.
---

Title: A Distributed Quantum Approximate Optimization Algorithm Simulator for Engineering Design Optimization
Link: https://arxiv.org/abs/2606.26297
Tags: arxiv, csdc
Abstract/Content: arXiv:2606.26297v3 Announce Type: replace Abstract: This paper presents a Qiskit-compatible distributed quantum approximate optimization algorithm (DQAOA) simulator for quadratic unconstrained binary optimization (QUBO) problems arising in engineering design and decision applications. The open-source simulator is available through the RAISE LAB website and GitHub repository, with README documentation for installation, input formatting, configurable parameters, and example workflows. The package addresses the need for a reusable simulator that can solve and compare QUBO instances across different QAOA execution modes. It supports monolithic QAOA on a single quantum processing unit (QPU) and distributed QAOA across a user-specified number of QPUs with configurable capacities. The workflow canonicalizes the QUBO model, maps it to a cost Hamiltonian, allocates variables across QPUs, identifies local and cross-QPU couplings, and constructs the corresponding circuits. Runtime optimizations, including parameterized circuit reuse, objective reuse at fixed depth, batched evaluations, and parallel multi-start execution, reduce repeated overhead. A Streamlit graphical user interface is also provided for entering or uploading QUBO instances, configuring solver settings, running selected modes, and visualizing solution-quality metrics without editing Python scripts. The package is demonstrated on standalone QUBO benchmarks and a power generation unit commitment application. In the unit commitment case, brute force, monolithic QAOA, and distributed QAOA recover the same commitment bitstring and operating cost. Across multiple case studies, the simulator produces results consistent with classical monolithic QAOA references in terms of optimal bitstrings and costs. Staged runtime analysis shows substantial runtime reduction across implementation stages, while distributed QAOA remains more demanding because cross-QPU couplings require remote operations.
---

Title: Energy-Efficient Multimodal Inference Serving with Tri-serve
Link: https://arxiv.org/abs/2606.29629
Tags: arxiv, csdc
Abstract/Content: arXiv:2606.29629v2 Announce Type: replace Abstract: Multimodal model inference creates substantial energy demand with growing performance requirements. Within GPUs, power is autonomously managed by an on-board power management unit (PMU), which makes frequency boosting/throttling decisions. However, we find that these hardware-managed frequency decisions can cause significant power inefficiency. This work identifies three classes of power inefficiencies within modern multimodal inference serving: (1) inter-stage dependency stalls run at near maximum frequency despite being idle; (2) anti-correlation between auto-boost frequency and arithmetic intensity (A.I.) results in compute-bound phases (e.g., prefill) running at lower frequency and vice versa; and (3) thermal throttling degrades SM frequency and throughput. We propose Tri-serve, a software-based DVFS controller that jointly accounts for three classes of inefficiency -- inter-stage Dependency stalls, the Arithmetic-intensity effect on frequency and power, and the Thermal-throttling effect of high A.I. phases -- to deliver energy-efficient multimodal serving on commodity GPUs. We show that Tri-serve achieves 22% energy efficiency improvement with no latency or throughput impacts.
---

Title: Demystifying the Design Space and Best Practices for Heterogeneous LLM Inference and Serving
Link: https://arxiv.org/abs/2606.29708
Tags: arxiv, csdc
Abstract/Content: arXiv:2606.29708v2 Announce Type: replace Abstract: Heterogeneous prefill-decode (PD) inference is now in production: prefill on cost-efficient or supply-available accelerators, decode on bandwidth-strong ones, and KV state crossing mixed interconnects in mixed numerical formats. Each deployment makes these decisions on its own. What is missing is the picture across configurations-which decisions must be made jointly at the PD boundary, and which can be made independently. We propose a design space organized along four design axes-accelerator, precision, interconnect, and KV residency and the workload regime (stage pressure) they respond to. We show that only a subset of interactions among these factors become binding constraints once PD inference becomes heterogeneous. These interactions surface through three recurring boundary decisions: compute placement, KV representation, and KV ownership. The resulting analysis yields concrete guidance. Precision policy belongs to runtime roles rather than to a single system-wide setting, because the same low-bit format relieves different bottlenecks on each side of the boundary. KV transfer engines move bytes rather than tensor semantics, making representation compatibility an explicit boundary concern whenever producer and consumer differ. The KV handoff also carries a lifecycle-reservation, release, and failure recovery-that spans prefill and decode and requires explicit ownership. Two further interactions remain open. Cross-vendor and interconnect-related claims are stated as design guidance grounded in industrial deployment observations and source-code inspection of the runtimes involved.
---

Title: HSAP: A Hierarchical Sequence-aware Parallelism for Hybrid-Context Generative Models
Link: https://arxiv.org/abs/2606.30460
Tags: arxiv, csdc
Abstract/Content: arXiv:2606.30460v2 Announce Type: replace-cross Abstract: In this paper, we aim to combine the advantages of existing sequence parallelism paradigms and overcomes their drawbacks, the most serious of which is the incapability to correctly compute causal attention on the hybrid-context packed sequences, in a stronger sequence parallelism framework. The practical technique of packing sequences for efficiently pretraining and fine-tuning large language models causes cross-contamination problem in attention computation, which can be effectively solved when no parallelism in the sequence length dimension is taken. However, in sequence parallelism, existing approaches either ignore the scenario of hybrid-context sequences or conversely sacrifice and limit parallelism degree for supporting the scenario. To this end, we innovatively propose an efficient Sequence-Aware Parallelism algorithm to conquer the obstacles of intensive tensor transmission and partial attention computation across multiple device groups. Our algorithm utilizes JIT (Just-In-Time) compilation to optimize the communication strategy of all device groups in NCCL level. Further, we integrate existing sequence parallelism paradigms into a Hierarchical Sequence-Aware Parallelism framework which benefits from our sequence-aware algorithm. We additionally elaborate on the memory and communication overhead management of the hierarchical framework to optimize its performance. Through multiple experiments, we demonstrate that our proposed approach outperform other state-of-the-arts sequence parallelism approches in multiple metrics.
---

Title: Elastic Scheduling of Intermittent Query Processing in a Cluster Environment
Link: https://arxiv.org/abs/2605.08601
Tags: arxiv, csdb
Abstract/Content: arXiv:2605.08601v4 Announce Type: replace Abstract: Many applications process a stream of tuples over a window duration, and require the results within a specified deadline after the end of the window. For such scenarios, processing tuples intermittently (in batches) instead of eagerly processing tuples as they arrive significantly reduces the overall cost. Earlier work on intermittent query processing has addressed only fixed environments. In this paper, we propose scheduling schemes for batched processing of tuples, in an elastic parallel environment, scaling nodes up or down. Our scheduling schemes ensure to meet the deadlines, while incurring minimum cost. Our schemes also handle multiple concurrent queries, the arrival of new queries, and input rate variations. We have implemented our schemes on top of Apache Spark, in the AWS EMR environment, and evaluated performance with both TPC-H and Yahoo Streaming datasets. Our experimental results show that our scheduling algorithms significantly outperform alternatives, such as using a fixed set of nodes without elasticity, or using Spark streaming.
---

Title: Knowledge Graphs as the Missing Data Layer for LLM-Based Industrial Asset Operations
Link: https://arxiv.org/abs/2605.26874
Tags: arxiv, csai
Abstract/Content: arXiv:2605.26874v3 Announce Type: replace Abstract: LLM-based agents for industrial asset operations show limited accuracy when reasoning over flat document stores. AssetOpsBench (KDD 2026) establishes that GPT-4 agents achieve 65% on 139 industrial maintenance scenarios, and compares LLM orchestration paradigms (Agent-As-Tool vs. Plan-Execute) on a fixed data layer. We ask the orthogonal question: how much does the data model behind the tools matter? We treat a typed knowledge graph as a grounding substrate and route each question by how it is best answered: (i) LLM-generated Cypher for structured retrieval, which lifts the same GPT-4 model from 65% to 82-83%; (ii) native graph and optimization primitives, with no LLM, reaching 99% on graph-answerable scenarios; and (iii) generation-augmented knowledge (GAK) for answers absent from the data -- the engine's agent materializes the missing facts as provenance-tagged graph nodes, then answers. A recurring theme is inverted LLM usage: we constrain the LLM to query generation or one-shot enrichment from a typed schema and let the graph execute deterministically. On the 88 real AssetOpsBench failure-mode scenarios the benchmark itself flags non-deterministic -- ten equipment types absent from the graph -- GAK lifts answerability from zero to 100% of equipment types and answers 81.8% of scenarios, every materialized fact tagged source:LLM-derived for auditability. We also contribute 40 graph-native scenarios. For structured operational domains the data layer -- not the LLM orchestration -- is the primary lever, and a typed knowledge graph serves as a grounding substrate between raw industrial data and LLM reasoning.
---

Title: Explaining Rankings with Hidden Group Bonuses
Link: https://arxiv.org/abs/2605.29444
Tags: arxiv, csds
Abstract/Content: arXiv:2605.29444v2 Announce Type: replace-cross Abstract: Determining a linear utility function that correlates with observed candidate rankings is a foundational problem with applications in domains such as admissions, hiring, and recommendation systems, e.g., [Storandt and Funke, AAAI'19, Zhang et al., KDD'23, Wang et al., ICDE'24 (best paper award), Chen and Wong, VLDB'24]. Traditionally, these models assume full visibility into the feature sets used to determine the utility score. However, real-world scenarios often involve sensitive attributes that are hidden or partially observed, yet may influence outcomes through additive bonuses designed to promote fairness, as in [Gale and Marian, ICDE'24]. Motivated by such practical concerns, we study a variant of the ranking explanation problem where sensitive features are unobserved but may influence candidate rankings through group-specific linear boosts. We present a formal framework for modeling this problem and develop an algorithmic solution that leverages constraint satisfaction and automated reasoning techniques to jointly infer the linear scoring parameters and latent group bonuses consistent with the observed rankings. We further show that determining a satisfying linear function with group-specific bonuses is \textsf{NP}-hard in general, but when the feature dimension and the number of groups are constant, the problem admits a polynomial-time solution. Our approach is the first to address this nuanced variant, which captures key real-world challenges in fair ranking and admission systems. We perform extensive experiments on both real-world and synthetic datasets, demonstrating that our method effectively recovers hidden bonus structures and provides faithful explanations of observed ranking outcomes.
---

Title: Understanding Domain-Aware Distribution Alignment in Budgeted Entity Matching
Link: https://arxiv.org/abs/2606.27342
Tags: arxiv, csai
Abstract/Content: arXiv:2606.27342v2 Announce Type: replace Abstract: Entity Matching (EM) is a core operation in the data integration pipeline, where records from different sources are compared to determine whether they refer to the same real-world entity. Recent work has incorporated domain information and low-resource learning techniques to better adapt EM systems to realistic settings. While these approaches have demonstrated strong performance, it remains unclear how they behave under varying data constraints and levels of supervision in practice. In this paper, we investigate a state-of-the-art method for low-resource, domain-aware EM--BEACON--and study how its performance is affected by different algorithmic choices and data availability conditions. We conduct a series of targeted experiments to evaluate these variations, providing deeper insight into the role of distribution alignment and the behavior of the BEACON framework.
---

Title: Test-Time Verification for Text-to-SQL via Outcome Reward Models
Link: https://arxiv.org/abs/2606.30851
Tags: arxiv, csai
Abstract/Content: arXiv:2606.30851v1 Announce Type: cross Abstract: Improving the reliability of large language models (LLMs) at inference time is a central challenge in structured reasoning tasks such as Text-to-SQL. Common test-time inference strategies, including Best-of-N sampling and Majority Voting, rely on heuristic signals such as execution success or output frequency, which provide limited semantic discrimination across candidate outputs. In this work, we study Outcome Reward Models (ORMs) as learned semantic scoring functions for test-time verification in Text-to-SQL. While ORMs have been previously explored for test-time scaling and alignment, their application to structured query generation remains underexplored. We introduce GradeSQL, a scalable framework for training task-specific ORMs via automated candidate generation and execution-based labeling, enabling verifier training without manual annotation. We integrate ORMs into a verification-driven Best-of-N pipeline and evaluate our approach on the BIRD and Spider benchmarks across multiple open-source LLM families. ORM-based selection consistently outperforms execution-based Best-of-N and Majority Voting, with gains of up to +4.33% on BIRD and +2.10% on Spider. We further show that ORMs scale effectively with larger candidate sets and yield stronger improvements on complex queries. Overall, our results demonstrate that ORM-based verification provides a simple, effective, and scalable alternative to heuristic test-time selection strategies for Text-to-SQL. Code datasets and models are publicly available.
---

Title: DA-Studio: An Agentic System for End-to-End Data Analysis
Link: https://arxiv.org/abs/2606.31423
Tags: arxiv, csai
Abstract/Content: arXiv:2606.31423v1 Announce Type: new Abstract: Real-world data analysis is a multi-step process over heterogeneous inputs rather than merely producing a final answer. A practical system should autonomously organize multi-step workflows, execute generated code in a sandboxed and controllable environment, and remain inspectable through visible action traces and intermediate artifacts. Existing LLM-based analysis tools, however, often emphasize isolated subtasks, leaving limited support for complete execution-grounded workflows. We present DA-Studio (Data Analysis Studio), an interactive web-based demo system for end-to-end data analysis that is autonomous, sandboxed, and inspectable. DA-Studio integrates an action-structured analysis backend, a sandboxed execution workspace, and a browser interface for task setup, streamed action traces, artifact preview, code editing and rerunning, and report export. Through iterative action generation, code execution, and feedback incorporation, it incrementally constructs executable analysis steps from raw files and natural-language requests while exposing intermediate results and artifacts throughout the process.
---

Title: Large Databases Need Small, Open-Weight Language Models
Link: https://arxiv.org/abs/2606.31808
Tags: arxiv, csai
Abstract/Content: arXiv:2606.31808v1 Announce Type: cross Abstract: Language model systems built around proprietary APIs often operate on a token-based cost model. This becomes prohibitively expensive in the context of large databases, where LM-enhanced relational operators can incur costs exceeding $10,000 for a single set of experiments, hindering thorough research and practical deployment. In this paper, we demonstrate that quantized, open-weight models running locally on just 16GB of VRAM can match or exceed the accuracy of closed-source counterparts at lower latency and a fraction of the price, challenging the prevailing assumption that closed-source LM APIs are necessary for effective LM-database integration. We present and analyze the key system optimizations required to efficiently deploy these open-weight models within an LM-DB system. By integrating these local models into the BlendSQL v0.1.0 framework, we demonstrate a 390x reduction in overall costs and 3.8x reduction in latency compared to a proprietary LM API. We make our code available at https://github.com/CapitalOne-Research/play-by-the-type-rules/tree/main/sembench.
---

Title: Clean Me If You Can: A Large Collection of Real-World Addresses for Data Cleaning Benchmarking
Link: https://arxiv.org/abs/2606.31983
Tags: arxiv, csdb
Abstract/Content: arXiv:2606.31983v1 Announce Type: new Abstract: There has been extensive research on automating and scaling data cleaning, i.e., the detection and correction of erroneous values in tabular data. Yet, existing approaches often perform well only within controlled environments. One of the major bottlenecks in data cleaning research is the lack of real-world datasets. In this paper, we address this gap by providing a large, dirty dataset with postal entries and their corresponding ground truth. We discuss the design decisions and challenges for obtaining the dataset. We demonstrate the limitations of existing cleaning approaches when faced with our proposed datasets and derive guidelines for future research.
---

Title: A Survey of Quantum Alternatives to Randomized Algorithms: Monte Carlo Integration and Beyond
Link: https://arxiv.org/abs/2303.04945
Tags: arxiv, csds
Abstract/Content: arXiv:2303.04945v3 Announce Type: replace-cross Abstract: Monte Carlo sampling is a powerful toolbox of algorithmic techniques widely used for a number of applications wherein some noisy quantity, or summary statistic thereof, is sought to be estimated. In this paper, we survey the literature for implementing Monte Carlo procedures using quantum circuits, focusing on the potential to obtain a quantum advantage in the computational speed of these procedures. We revisit the quantum algorithms that could replace classical Monte Carlo and then consider both the existing quantum algorithms and the potential quantum realizations that include adaptive enhancements as alternatives to the classical procedure.
---

Title: Near-Optimal Parameter Tuning of Level-1 QAOA for Ising Models
Link: https://arxiv.org/abs/2501.16419
Tags: arxiv, csds
Abstract/Content: arXiv:2501.16419v3 Announce Type: replace-cross Abstract: The Quantum Approximate Optimisation Algorithm (QAOA) is a hybrid quantum-classical algorithm for solving combinatorial optimisation problems. QAOA encodes solutions into the ground state of a Hamiltonian, approximated by a $p$-level parameterised quantum circuit composed of problem and mixer Hamiltonians, with parameters optimised classically. While deeper QAOA circuits can offer greater accuracy, practical applications are constrained by complex parameter optimisation and physical limitations such as gate noise, restricted qubit connectivity, and state-preparation-and-measurement errors, limiting implementations to shallow depths. This work focuses on QAOA$_1$ (QAOA at $p=1$) for QUBO problems, represented as Ising models. Despite QAOA$_1$ having only two parameters, $(\gamma, \beta)$, we show that their optimisation is challenging due to a highly oscillatory landscape, with oscillation rates increasing with the problem size, density, and weight. This behaviour necessitates high-resolution grid searches to avoid distortion of cost landscapes that may result in inaccurate minima. We propose an efficient optimisation strategy that reduces the two-dimensional $(\gamma, \beta)$ search to a one-dimensional search over $\gamma$, with $\beta^*$ computed analytically. We establish the maximum permissible sampling period required to accurately map the $\gamma$ landscape and provide an algorithm to estimate the optimal parameters in polynomial time. Furthermore, we rigorously prove that for regular graphs on average, the globally optimal $\gamma^* \in \mathbb{R}^+$ values are concentrated very close to zero and coincide with the first local optimum, enabling gradient descent to replace exhaustive line searches. This approach is validated using Recursive QAOA (RQAOA), where it consistently outperforms both coarsely optimised RQAOA and semidefinite programs across all tested QUBO instances.
---

Title: Testing Suffixient Sets
Link: https://arxiv.org/abs/2506.08225
Tags: arxiv, csds
Abstract/Content: arXiv:2506.08225v2 Announce Type: replace Abstract: Suffixient sets are a novel prefix array (PA) compression technique based on subsampling PA (rather than compressing the entire array like previous techniques used to do): by storing very few entries of PA (in fact, a compressed number of entries), one can prove that pattern matching via binary search is still possible provided that random access is available on the text. In this paper, we tackle the problems of determining whether a given subset of text positions is (1) a suffixient set or (2) a suffixient set of minimum cardinality. We provide linear-time algorithms solving these problems.
---

Title: SPAM Tolerance for Pauli Error Estimation
Link: https://arxiv.org/abs/2510.00230
Tags: arxiv, csds
Abstract/Content: arXiv:2510.00230v2 Announce Type: replace-cross Abstract: The Pauli channel is a fundamental model of noise in quantum systems, motivating the task of Pauli error estimation. We present an algorithm that builds on the reduction to Population Recovery introduced in [FO21]. Addressing an open question from that work, our algorithm has the key advantage of robustness against even severe state preparation and measurement (SPAM) errors. To tolerate SPAM, we must analyze Population Recovery on a combined $Z$-channel/bit-flip channel, which necessitates extending the complex analysis techniques from [PSW17, DOS17]. For $n$-qubit channels, our Pauli error estimation algorithm requires only $\exp(n^{1/3})$ unentangled state preparations and measurements, improving on previous SPAM-tolerant algorithms that had $2^n$-dependence even for restricted families of Pauli channels. We also give evidence that no SPAM-tolerant method can make asymptotically fewer than $\exp(n^{1/3})$ uses of the channel.
---

Title: Counting Patterns in Degenerate Graphs in Constant Space
Link: https://arxiv.org/abs/2511.04258
Tags: arxiv, csds
Abstract/Content: arXiv:2511.04258v2 Announce Type: replace Abstract: For a fixed pattern graph, we study the algorithmic complexity of counting homomorphisms, subgraph isomorphisms, and induced subgraph isomorphisms into an $n$-vertex, $d$-degenerate host graph. Bressan (Algorithmica, 2021) introduced the notion of DAG treewidth and showed that counting homomorphisms and induced subgraphs can be performed efficiently using dynamic programming that requires polynomial space. In this work, we introduce a new graph parameter, called DAG treedepth, which enables efficient divide-and-conquer algorithms for counting homomorphisms in $d$-degenerate host graphs using only constant space. Bera, Gishboliner, Levanzov, Seshadhri, and Shapira (SODA, 2021) showed that a pattern graph has DAG treewidth one if and only if it contains no induced cycle of length at least six. This induced minor characterization leads to linear-time and linear-space algorithms. Building on this line of work, we derive an induced-minor characterization of graphs with DAG treedepth at most two that uses only constant space. Recently, Paul-Pena and Seshadhri (ICALP, 2025) proved that all pattern graphs on at most nine vertices can be counted in subquadratic time using polynomial space. We show that every pattern graph on at most nine vertices can be counted as an induced subgraph in $O(n^3)$ time using only constant space. Moreover, we show that patterns on at most eleven vertices can be counted in $O(n^2)$ time using polynomial space. Finally, we present a constant-space algorithm for counting induced subgraphs that matches the running time of Bressan algorithm. We further show that, when polynomial space is allowed, homomorphisms, subgraph isomorphisms, and induced subgraph isomorphisms can be counted faster than Bressan algorithm. In addition, we establish several other results related to DAG treewidth and DAG treedepth that may be of independent interest.
---

Title: Greedy Completion for Weighted $(\alpha,\beta)$-Spanners
Link: https://arxiv.org/abs/2603.17047
Tags: arxiv, csds
Abstract/Content: arXiv:2603.17047v3 Announce Type: replace Abstract: We study $(\alpha,\beta)$-spanners for weighted graphs. We propose a simple greedy completion procedure which starts from a sparse initial graph, and repeatedly fixes pairs of vertices with a bad stretch, generalizing Knudsen's additive completion [SWAT '14]. As an application, we construct $(k,k-1)$-spanners for weighted graphs of size $\tilde{O}(n^{1+1/k})$, which were previously unknown.
---

Title: The Geometry of Efficient Nonconvex Sampling
Link: https://arxiv.org/abs/2603.25622
Tags: arxiv, csds
Abstract/Content: arXiv:2603.25622v2 Announce Type: replace Abstract: We present an efficient algorithm for uniformly sampling from an arbitrary compact body $\mathcal{X} \subset \mathbb{R}^n$ from a warm start under isoperimetry and a natural volume growth condition. Our result provides a substantial common generalization of known results for convex bodies and star-shaped bodies. The complexity of the algorithm is polynomial in the dimension, the Poincar\'e constant of the uniform distribution on $\mathcal{X}$ and the volume growth constant of the set $\mathcal{X}$.
---

Title: Handicap reduction for linear complementarity problems
Link: https://arxiv.org/abs/2605.10701
Tags: arxiv, csds
Abstract/Content: arXiv:2605.10701v2 Announce Type: replace-cross Abstract: Linear Complementarity Problems (LCPs) with sufficient matrices form an important subclass of LCPs, and it remains a significant open question whether problems in this class can be solved in polynomial time. Kojima, Megiddo, Noma, and Yoshise gave an Interior Point Algorithm (IPA) in 1991, that can solve LCPs with sufficient matrices in time bounded polynomially in the input size and the so-called handicap number $\hat\kappa(M)$ of the coefficient matrix $M$. However, this value can be exponentially large in the bit encoding length. In fact, no upper bounds were previously known on $\hat\kappa(M)$. Settling an open question raised in de Klerk and E.-Nagy (Math Programming, 2011), we give an exponential upper bound on $\hat\kappa(M)$ in the bit-complexity of $M$. This is based on a new characterization of sufficient matrices. The new characterization also leads to a simple new proof of V\"aliaho's theorem on the equivalence of sufficient and $\mathcal{P}^*$-matrices (Linear Algebra and its Applications, 1996). Noting that one can obtain an equivalent LCP by rescaling the rows and columns by a positive diagonal matrix, we define $\hat\kappa^\star(M)$ as the best possible handicap number achievable under such rescalings. Our second main result is an algorithm for LCPs with sufficient matrices, where the running time is polynomially bounded in the input size and in the optimized value $\hat\kappa^\star(M)$. This algorithm is based on the observation that the set of near-optimal row-rescalings forms a convex set. Our algorithm combines the Ellipsoid Method over the set of row rescalings, and an IPA with running time dependent on the handicap number of the matrix. If the IPA fails to solve the LCP in the desired running time, it provides a separation oracle to the Ellipsoid Method to find a better rescaling.
---

Title: $\texttt{bucket-graph-spprc}$: an extensible C++ library for the shortest path problem with resource constraints
Link: https://arxiv.org/abs/2606.30847
Tags: arxiv, csds
Abstract/Content: arXiv:2606.30847v1 Announce Type: cross Abstract: We present $\texttt{bucket-graph-spprc}$ ($\texttt{bgspprc}$ for short), an open-source, header-only C++23 library for the shortest path problem with resource constraints (SPPRC), the pricing subproblem at the heart of branch-cut-and-price for vehicle routing and related problems. The library implements the bucket-graph labelling algorithm of Sadykov, Uchoa and Pessoa (2021), with bidirectional labelling, across-arc concatenation, bucket fixing and arc elimination, and a structure-of-arrays label store with SIMD-accelerated dominance. Its central design feature is a compile-time resource concept: a new SPPRC variant is added by implementing a fixed seven-function interface, and resources compose into a label state with no runtime dispatch, the state layout fixed at compile time. Five resources ship built in: time/capacity, ng-path elementarity relaxation, rank-1 cuts, cumulative cost, and pickup-and-delivery. In a reproducible, head-to-head comparison on shared public instances at an identical bound, $\texttt{bgspprc}$ outperforms PathWyse (Salani, Basso and Giuffrida, 2024), the main open-source comparator, by $1.3\times$--$2.35\times$ in shifted geometric mean (and by $1.3\times$--$2.3\times$ even when itself run single-threaded), and runs within $1.9\times$--$2.4\times$ of parallel pull labelling (Petersen and Spoorendonk, 2025), a different labelling technique for the same problem. The library, benchmark scripts, and pinned instances are publicly available.
---

Title: Algorithms and complexity for geodetic sets on interval and chordal graphs
Link: https://arxiv.org/abs/2606.30882
Tags: arxiv, csds
Abstract/Content: arXiv:2606.30882v1 Announce Type: new Abstract: We study the computational complexity of finding the geodetic number of a graph on chordal graphs and interval graphs. A set $S$ of vertices of a graph $G$ is a \textit{geodetic set} if every vertex of $G$ lies in a shortest path between some pair of vertices of $S$. The \textsc{Minimum Geodetic Set (MGS)} problem is to find a geodetic set with minimum cardinality of a given graph. We show that \textsc{Minimum Geodetic Set} is fixed parameter tractable for chordal graphs when parameterized by its \emph{tree-width} (which equals its clique number). This implies a polynomial-time algorithm for $k$-trees, for fixed $k$. Then, we show that \textsc{Minimum Geodetic Set} is NP-hard on interval graphs, thereby answering a question of Ekim et al. (LATIN, 2012), who showed that \textsc{Minimum Geodetic Set} is polynomial-time solvable on proper interval graphs. As interval graphs are very constrained, to prove the latter result, we design a rather sophisticated reduction technique to work around their inherent linear structure.
---

Title: Corruption Robust Offline Reinforcement Learning with Human Feedback
Link: https://arxiv.org/abs/2402.06734
Tags: arxiv, csai
Abstract/Content: arXiv:2402.06734v2 Announce Type: replace-cross Abstract: We study data corruption robustness for reinforcement learning with human feedback (RLHF) in an offline setting. Given an offline dataset of pairs of trajectories along with feedback about human preferences, an $\varepsilon$-fraction of the pairs is corrupted (e.g., feedback flipped or trajectory features manipulated), capturing an adversarial attack or noisy human preferences. We aim to design algorithms that identify a near-optimal policy from the corrupted data, with provable guarantees. Existing theoretical works have separately studied the settings of corruption robust RL (learning from scalar rewards directly under corruption) and offline RLHF (learning from human feedback without corruption); however, they are inapplicable to our problem of dealing with corrupted data in offline RLHF setting. To this end, we design novel corruption robust offline RLHF methods under various assumptions on the coverage of the data-generating distributions. At a high level, our methodology robustifies an offline RLHF framework by first learning a reward model along with confidence sets and then learning a pessimistic optimal policy over the confidence set. Our key insight is that learning optimal policy can be done by leveraging an offline corruption-robust RL oracle in different ways (e.g., zero-order oracle or first-order oracle), depending on the data coverage assumptions. To our knowledge, ours is the first work that provides provable corruption robust offline RLHF methods.
---

Title: Perturbation Effects on Robustness and Individual Fairness
Link: https://arxiv.org/abs/2404.01356
Tags: arxiv, csai
Abstract/Content: arXiv:2404.01356v4 Announce Type: replace-cross Abstract: Deep neural networks are vulnerable to adversarial perturbations that can simultaneously degrade prediction robustness and individual fairness across diverse application settings. However, existing evaluation protocols typically assess these dimensions in isolation, thereby obscuring critical failure modes. To bridge this gap, we formalize Robust Individual Fairness (RIF): under semantic-preserving (truth-condition-preserving) perturbations, predictions should remain both correct with respect to the ground truth and invariant across semantically equivalent individuals. To surface RIF violations in practice, we introduce RIFair, a black-box adversarial framework that leverages a decoupled perturbation strategy to construct semantically preserved yet unrobust and/or unfair instance pairs. Experiments across multiple model architectures and real-world textual datasets show that robustness-only or fairness-only metrics often miss Robust Biased and Unrobust Fair behaviors. RIFair}reliably exposes these hidden vulnerabilities, supporting RIF as a necessary criterion for trustworthy model assessment. The experimental code is publicly available at https://github.com/Xuran-LI/RIFair.
---

Title: Learning by Surprise: Adaptive Mitigation of Model Collapse in Large Language Models
Link: https://arxiv.org/abs/2410.12341
Tags: arxiv, csai
Abstract/Content: arXiv:2410.12341v4 Announce Type: replace-cross Abstract: As AI-generated content increasingly populates the web, generative AI models are at growing risk of being trained on their own outputs, a process known as AI autophagy. This feedback loop has been shown to induce model collapse, typically characterized by a loss of diversity in generated content. However, existing work offers a limited understanding of this phenomenon and relies on mitigation strategies that assume access to human-authored data. In this paper, we conduct extensive simulations across multiple datasets and LLMs to address key gaps in the study of model collapse. First, we introduce model-intrinsic measures based on next-token probability distributions, showing that model collapse corresponds to an increasing concentration of probability mass on a small set of tokens. Second, we demonstrate that model collapse is also associated with a loss of common sense, as measured by a decline in commonsense inference accuracy. Third, we identify perplexity (a measure of model "surprise") as a key driver of collapse: fine-tuning on the least "surprising" documents leads to more severe degeneration. Building on this insight, we propose a perplexity-based filtering strategy that prioritizes high-surprise documents during fine-tuning. Unlike existing approaches, our method does not require distinguishing between human-authored and AI-generated content. Across datasets and LLM families, this strategy consistently mitigates model collapse, achieving performance comparable to, and in some cases better than, human-data baselines, while substantially reducing the concentration of next-token probabilities. Overall, our results provide a unified, model-centric understanding of model collapse and suggest practical, scalable strategies for training generative AI systems in increasingly synthetic environments.
---

Title: Compositional Concept-Based Neuron-Level Interpretability for Deep Reinforcement Learning
Link: https://arxiv.org/abs/2502.00684
Tags: arxiv, csai
Abstract/Content: arXiv:2502.00684v2 Announce Type: replace-cross Abstract: Deep reinforcement learning (DRL) has successfully addressed many complex control problems. However, the neural networks representing policies or values remain opaque, undermining trust in high-stakes applications. While concept-based methods have shown promise in deciphering internal representations in computer vision, applying them to DRL is impeded by the absence of pre-defined semantic concepts in continuous state spaces. In this work, we propose a novel concept-based explanation framework designed to provide fine-grained, neuron-level insights into DRL models. Unlike previous approaches that rely on manual feature engineering, our framework automatically aligns neuron activations with logical formulas composed of semantic predicates. To bridge the gap between continuous signals and symbolic reasoning, we introduce a value-sensitive discretization mechanism that transforms raw state features into interpretable atomic concepts. This ensures that the vocabulary used for explanation captures strategic decision boundaries relevant to the agent's value assessment. By composing these interpretable concepts and matching them with neuron behaviors, we derive explicit explanations for the network's internal representations. Experimental results on both continuous and discrete environments demonstrate that our method effectively identifies meaningful decision-making patterns, offering faithful explanations that align with human intuition.
---

Title: Mantis: Lightweight Foundation Model for Time Series Classification
Link: https://arxiv.org/abs/2502.15637
Tags: arxiv, csai
Abstract/Content: arXiv:2502.15637v2 Announce Type: replace-cross Abstract: While foundation models have revolutionized various domains, their application to time series classification remains rather under-explored, with existing literature predominantly focused on forecasting. To bridge this gap, we introduce \textbf{Mantis}, a transformer-based foundation model pre-trained exclusively on synthetic data via self-supervised contrastive learning. We demonstrate that effective tokenization is critical to unlocking the full potential of transformers, proposing a novel token generator unit. Furthermore, we introduce an enhanced test-time methodology that bridges the performance gap between Mantis and strong specialized approaches by leveraging intermediate-layer representations, self-ensembling, and cross-model embedding fusion. Extensive experiments demonstrate that Mantis establishes a new state-of-the-art, outperforming existing foundation models across four diverse dataset collections covering various application domains.
---

Title: Verify when Uncertain: Beyond Self-Consistency in Black Box Hallucination Detection
Link: https://arxiv.org/abs/2502.15845
Tags: arxiv, csai
Abstract/Content: arXiv:2502.15845v2 Announce Type: replace-cross Abstract: Large Language Models (LLMs) often hallucinate, limiting their reliability in sensitive applications. In black-box settings, several self-consistency-based techniques have been proposed for hallucination detection. We empirically show that these methods perform nearly as well as a supervised (black-box) oracle, leaving limited room for further gains within this paradigm. To address this limitation, we explore cross-model consistency checking between the target model and an additional verifier LLM. With this extra information, we observe improved oracle performance compared to purely self-consistency-based methods. We then propose a budget-friendly, two-stage detection algorithm that calls the verifier model only for a subset of cases. It dynamically switches between self-consistency and cross-consistency based on an uncertainty interval of the self-consistency classifier. We provide a geometric interpretation of consistency-based hallucination detection methods through the lens of kernel mean embeddings, offering deeper theoretical insights. Extensive experiments on QA-style hallucination detection benchmarks show that this approach maintains high detection performance while significantly reducing computational cost.
---

Title: Artificial Intelligence in Sports: Insights from a Quantitative Survey among Sports Students in Germany about their Perceptions, Expectations, and Concerns regarding the Use of AI Tools
Link: https://arxiv.org/abs/2503.05785
Tags: arxiv, csai
Abstract/Content: arXiv:2503.05785v2 Announce Type: replace-cross Abstract: Generative Artificial Intelligence (AI) tools such as ChatGPT, Copilot, or Gemini have a crucial impact on academic research and teaching. Empirical data on how students perceive the increasing influence of AI, which different types of tools they use, what they expect from them in their daily academic tasks, and their concerns regarding the use of AI in their studies are still limited. The manuscript presents findings from a quantitative survey conducted among sports students of all semesters in Germany using an online questionnaire. It explores aspects such as students' usage behavior, motivational factors, and uncertainties regarding the impact of AI tools on academia in the future. Furthermore, the social climate in sports studies is being investigated to provide a general overview of the current situation of the students in Germany. Data collection took place between August and November 2023, addressing all sports departments at German universities, with a total of 262 students participating. Our Findings indicate that students have a strong interest in using AI tools in their studies, expecting them to improve their overall academic performance, understand the complexity of scientific approaches, and save time. They express confidence that the proliferation of AI will not compromise their critical thinking skills. Moreover, students are positive about integrating more AI-related topics into the curriculum and about lecturers adopting more AI-based teaching methods. However, our findings also show that students have concerns about plagiarism, lecturer preparedness and their own skills and future skill development.
---

Title: SAGE: A Search-AuGmented Evaluation of Large Language Models on Free-Form QA
Link: https://arxiv.org/abs/2504.07385
Tags: arxiv, csai
Abstract/Content: arXiv:2504.07385v3 Announce Type: replace-cross Abstract: As Large Language Models (LLMs) become increasingly used for question-answering (QA), relying on static, pre-annotated references for evaluation poses significant challenges in cost, scalability, and completeness. Meanwhile, using LLMs themselves as evaluators without external grounding remains unreliable for objective tasks, as they systematically over-accept incorrect answers, fabricate supporting rationales, and degrade sharply on questions that fall outside their training data. We propose Search-AuGmented Evaluation (SAGE), a framework to assess LLM outputs without fixed ground-truth answers. Unlike conventional metrics that compare to static references or depend solely on LLM-as-a-judge knowledge, SAGE acts as an agent that actively retrieves and synthesizes external evidence. It iteratively generates web queries, collects information, summarizes findings, and refines subsequent searches through reflection. By reducing dependence on static reference-driven evaluation protocols, SAGE offers a scalable and adaptive alternative for evaluating the factuality of LLMs. Experimental results on multiple free-form QA benchmarks show that SAGE achieves substantial to perfect agreement with human evaluations.
---

Title: TraCeS: Learning Per-Timestep Constraint-Violation Credit from Sparse Trajectory-Level Labels
Link: https://arxiv.org/abs/2504.12557
Tags: arxiv, csai
Abstract/Content: arXiv:2504.12557v3 Announce Type: replace-cross Abstract: Ensuring safe behavior in reinforcement learning (RL) is challenging when safety constraints are implicit and cannot be densely measured. In many settings, supervision is limited to coarse approvals or rejections of whole trajectories (e.g., whether a rollout remained within an unknown safety threshold). We propose TraCeS (Trajectory-based Constraint Estimation for Safety), a method for learning per-timestep violation credit from such sparse trajectory-level labels. TraCeS trains a sequential violation estimator whose per-step credits factorize the predicted probability that a trajectory has not yet violated the constraint, and integrates this learned signal into constrained policy optimization. The method requires neither a known cost function nor a known threshold, and remains compatible with standard continuous-control algorithms. We provide a theoretical analysis of the approximation gap introduced by the learning objective, and demonstrate empirically that TraCeS improves constraint satisfaction and feedback efficiency over baselines across multiple continuous-control benchmarks, including long-horizon tasks and settings with noisy or inconsistent labels.
---

Title: A Reproducible Benchmark of Lightweight CNNs: Accuracy, Efficiency, and the Impact of Pretrained Initialization
Link: https://arxiv.org/abs/2505.03303
Tags: arxiv, csai
Abstract/Content: arXiv:2505.03303v3 Announce Type: replace-cross Abstract: Lightweight convolutional neural networks are often compared using results obtained with different training recipes, input settings, and pretrained checkpoints. Such differences make architecture rankings difficult to interpret. This study presents a reproducible benchmark of seven established CNNs across CIFAR-10, CIFAR-100, and Tiny ImageNet under one common fine-tuning protocol. The evaluation reports top-1 accuracy, macro F1, top-5 accuracy, parameter count, FP32 parameter storage, and multiply-accumulate operations. EfficientNetV2-S records the highest observed top-1 accuracy on all three datasets, reaching 97.57%, 86.98%, and 78.73%. EfficientNet-B0 remains within 0.85 percentage points of EfficientNetV2-S across the three datasets while requiring only about 21% of its parameters and 14% of its multiply-accumulate operations on Tiny ImageNet. It therefore offers a favorable general balance between predictive performance and computational demand. MobileNetV3-Small is a strong candidate for ultra-low-resource settings. It uses about 40% of the parameters and 15% of the multiply-accumulate operations of EfficientNet-B0 while retaining competitive accuracy. A matched comparison of ImageNet-pretrained and randomly initialized EfficientNet-B0 and MobileNetV3-Small models shows that the pretrained advantage is substantially larger on CIFAR-100 and Tiny ImageNet than on CIFAR-10 under the fixed protocol. The results provide a focused reference for selecting established lightweight CNNs when predictive quality, parameter storage, and theoretical computation must be considered together.
---


** Raw LLM Output
* cs.DB (Databases)
** 🧐 Обзор
За последние сутки наблюдается смещение фокуса в сторону эластичности обработки запросов и качества данных для промышленного применения. Исследователи предлагают решения для динамического масштабирования ресурсов в кластерных средах и уделяют особое внимание созданию реалистичных бенчмарков для очистки данных.

** 🛠 Практика и Системы
- [[https://arxiv.org/abs/2605.08601][Elastic Scheduling of Intermittent Query Processing in a Cluster Environment]]
:WHAT: Схема планирования пакетной обработки кортежей в эластичной параллельной среде с масштабированием узлов.
:IMPACT: Позволяет соблюдать дедлайны при минимальных затратах, значительно превосходя фиксированные конфигурации Spark.

** 📄 Остальное
- [[https://arxiv.org/abs/2606.31983][Clean Me If You Can: A Large Collection of Real-World Addresses for Data Cleaning Benchmarking]] — представлен крупный набор грязных данных с адресами для тестирования алгоритмов очистки в реальных условиях.

* cs.AI (Artificial Intelligence)
** 🧐 Обзор
В области ИИ для систем данных ключевым трендом становится интеграция графов знаний и локальных моделей для снижения затрат и повышения точности. Наблюдается рост интереса к верификации генерации SQL-запросов и созданию автономных агентных систем для анализа данных.

** 🛠 Практика и Системы
- [[https://arxiv.org/abs/2605.26874][Knowledge Graphs as the Missing Data Layer for LLM-Based Industrial Asset Operations]]
:WHAT: Использование типизированного графа знаний как основы для маршрутизации запросов LLM вместо плоских документов.
:IMPACT: Повышает точность ответов с 65% до 82-83% и обеспечивает детерминизм в промышленных сценариях.

- [[https://arxiv.org/abs/2606.31808][Large Databases Need Small, Open-Weight Language Models]]
:WHAT:Deployment квантованных открытых моделей локально для интеграции с СУБД вместо дорогих API.
:IMPACT: Снижение затрат в 390 раз и задержек в 3.8 раза при сохранении точности для задач LM-DB.

- [[https://arxiv.org/abs/2606.31423][DA-Studio: An Agentic System for End-to-End Data Analysis]]
:WHAT: Интерактивная веб-система для автономного многошагового анализа данных с песочницей выполнения кода.
:IMPACT: Обеспечивает прозрачность и контролируемость рабочих потоков анализа данных через видимые следы действий.

- [[https://arxiv.org/abs/2606.30851][Test-Time Verification for Text-to-SQL via Outcome Reward Models]]
:WHAT: Фреймворк GradeSQL для обучения моделей вознаграждения (ORM) для верификации SQL-запросов во время инференса.
:IMPACT: Превосходит эвристические методы выбора Best-of-N, улучшая точность на сложных запросах.

** 📄 Остальное
- [[https://arxiv.org/abs/2606.27342][Understanding Domain-Aware Distribution Alignment in Budgeted Entity Matching]] — исследование влияния выравнивания распределений на эффективность сопоставления сущностей при ограниченных ресурсах.
- [[https://arxiv.org/abs/2410.12341][Learning by Surprise: Adaptive Mitigation of Model Collapse in Large Language Models]] — предложена стратегия фильтрации на основе перплексии для предотвращения коллапса моделей при обучении на синтетических данных.

* physics.soc-ph (Social Physics & Networks)
** 🧐 Обзор
В социальной физике усиливается интерес к моделированию взаимодействий высшего порядка и топологической устойчивости сетей. Исследования показывают, что групповая динамика и структурные ограничения циклов играют ключевую роль в стабильности социальных и инфраструктурных систем.

** 🕸 Графы и Алгоритмы
- [[https://arxiv.org/abs/2406.05026][Higher-order modeling of face-to-face interactions]]
:ALGO: Модель агентов, формирующих группы разного размера с учетом социальной привлекательности, вместо диадных связей.
:IMPACT: Воспроизводит распределение и персистентность групп в реальных взаимодействиях, что недоступно pairwise моделям.

- [[https://arxiv.org/abs/2603.17584][A dynamic mechanism for prevalence of triangles in competitive networks]]
:ALGO: Гипотеза о возникновении треугольников как следствии требования динамической устойчивости в системах Лотки-Вольтерры.
:IMPACT: Предлагает новое объяснение кластеризации в сетях через структурную сигнатуру стабилизирующей конкуренции.

- [[https://arxiv.org/abs/2604.19682][Cycle holonomy captures higher-order compatibility constraints in remote synchronization]]
:ALGO: Спектральный фреймворк, связывающий фрустрацию синхронизации с голономией циклов в обычных графах.
:IMPACT: Позволяет диагностировать глобальную несовместимость через локальные топологические ограничения без гиперграфов.

- [[https://arxiv.org/abs/2606.30685][Cascading Impacts of the USA--China Trade War on Global Oilseed Supply Chain]]
:ALGO: Линейное программирование для системы Input-Output, моделирующее каскадные disruptions и перераспределение торговли.
:IMPACT: Quantifies потери глобального выпуска и эффективность стратегий смягчения в сетях поставок.

** 📄 Остальное
- [[https://arxiv.org/abs/2604.05439][Scale-free congestion clusters in large-scale traffic networks: a continuum modeling study]] — макроскопические модели трафика способны воспроизводить скейлинг-инвариантные паттерны заторов.
- [[https://arxiv.org/abs/2604.13885][Role of volatility mixing in wealth condensation transition]] — смешение волатильности в сетях влияет на переход конденсации богатства и хвостовые распределения.
- [[https://arxiv.org/abs/2606.15106][Can homophily explain public underestimation of climate policy support?]] — гомофилия и медиа-предвзятость моделируют искажение восприятия общественной поддержки климатической политики.

* cs.DS (Data Structures & Algorithms)
** 🧐 Обзор
В алгоритмике доминируют работы по эффективному подсчету подграфов в разреженных графах и оптимизации маршрутизации. Также заметен прогресс в квантовых алгоритмах и библиотеках для задач с ограничениями ресурсов.

** 🕸 Графы и Алгоритмы
- [[https://arxiv.org/abs/2511.04258][Counting Patterns in Degenerate Graphs in Constant Space]]
:ALGO: Введен параметр DAG treedepth для подсчета гомоморфизмов и индуцированных подграфов с использованием постоянного пространства.
:IMPACT: Позволяет считать паттерны на до 9 вершин за O(n^3) в постоянном пространстве, улучшая алгоритмы динамического программирования.

- [[https://arxiv.org/abs/2603.17047][Greedy Completion for Weighted $(\alpha,\beta)$-Spanners]]
:ALGO: Процедура жадного дополнения для построения спаннеров в взвешенных графах, обобщающая аддитивное дополнения.
:IMPACT: Конструирует $(k,k-1)$-спаннеры размера $\tilde{O}(n^{1+1/k})$, ранее неизвестные для взвешенных графов.

- [[https://arxiv.org/abs/2606.30847][$\texttt{bucket-graph-spprc}$: an extensible C++ library for the shortest path problem with resource constraints]]
:ALGO: Библиотека для SPPRC с bucket-graph алгоритмом, SIMD-ускорением и compile-time ресурсами.
:IMPACT: Превосходит открытые аналоги в 1.3–2.35 раза, предоставляя эффективный инструмент для vehicle routing.

- [[https://arxiv.org/abs/2606.30882][Algorithms and complexity for geodetic sets on interval and chordal graphs]]
:ALGO: Доказана FPT-разрешимость для хордальных графов и NP-трудность для интервальных графов задачи о минимальном геодезическом множестве.
:IMPACT: Уточняет границы вычислительной сложности для задач покрытия путей в специализированных классах графов.

** 📄 Остальное
- [[https://arxiv.org/abs/2303.04945][A Survey of Quantum Alternatives to Randomized Algorithms: Monte Carlo Integration and Beyond]] — обзор квантовых алгоритмов замены процедур Монте-Карло для ускорения вычислений.
- [[https://arxiv.org/abs/2501.16419][Near-Optimal Parameter Tuning of Level-1 QAOA for Ising Models]] — эффективная стратегия оптимизации параметров QAOA глубины 1 через сведение к одномерному поиску.

* cs.DC (Distributed Computing)
** 🧐 Обзор
Распределенные системы фокусируются на оптимизации инференса больших языковых моделей и устойчивости к византийским сбоям. Ключевыми направлениями стали управление тепловыми режимами в орбитальных ЦОД и гетерогенная обработка запросов.

** 🛠 Практика и Системы
- [[https://arxiv.org/abs/2602.11688][GORGO: Online Tuning for Cross-Region Network-Aware LLM Serving]]
:WHAT: Прокси-архитектура для балансировки нагрузки LLM с учетом задержек сети и локальности KV-cache.
:IMPACT: Улучшает p95 TTFT на 6.9-15.5% за счет эволюционной настройки параметров политики маршрутизации.

- [[https://arxiv.org/abs/2606.29629][Energy-Efficient Multimodal Inference Serving with Tri-serve]]
:WHAT: Программный контроллер DVFS, учитывающий зависимости стадий, арифметическую интенсивность и тепловое троттлинг.
:IMPACT: Повышает энергоэффективность на 22% без влияния на задержки при обслуживании мультимодальных моделей.

- [[https://arxiv.org/abs/2606.29708][Demystifying the Design Space and Best Practices for Heterogeneous LLM Inference and Serving]]
:WHAT: Анализ пространства дизайна для гетерогенного prefill-decode инференса с разделением ускорителей.
:IMPACT: Формирует рекомендации по управлению KV-памятью и точностью на границах разнородных систем.

- [[https://arxiv.org/abs/2601.04930][Privacy-Preserving Federated Averaging with Byzantine Aggregators in Asynchronous Networks]]
:WHAT: Протокол безопасной агрегации для асинхронных сетей, устойчивый к византийским агрегаторам и задержкам.
:IMPACT: Закрывает разрыв между теоретическими предположениями и реальными ненадежными распределенными настройками.

- [[https://arxiv.org/abs/2606.26150][Hot AI in Cold Space: Thermal-Crosstalk-Aware Scheduling for Sustainable Orbital AI Clusters]]
:WHAT: Фреймворк Thermal-Load Balancing (TLB) для миграции workload в орбитальных ЦОД на основе температурных данных.
:IMPACT: Решает проблему теплового_cross-talk и продлевает срок службы оборудования, снижая космический мусор.

** 🕸 Графы и Алгоритмы
- [[https://arxiv.org/abs/2606.18966][A Composable CRDT Layer for Byzantine-Resilient Deterministic Reconstruction]]
:ALGO: Модель детерминированной реконструкции состояния для CRDT, разделяющая распространение обновлений и вывод состояния.
:IMPACT: Гарантирует сходимость при византийском поведении без координации, позволяя внешние механизмы консенсуса.

** 📄 Остальное
- [[https://arxiv.org/abs/2606.30460][HSAP: A Hierarchical Sequence-aware Parallelism for Hybrid-Context Generative Models]] — иерархический параллелизм последовательностей для эффективного обучения на гибридных контекстах.
- [[https://arxiv.org/abs/2606.26297][A Distributed Quantum Approximate Optimization Algorithm Simulator for Engineering Design Optimization]] — симулятор распределенного QAOA для задач инженерной оптимизации с поддержкой нескольких QPU.
- [[https://arxiv.org/abs/2606.22973][Decentralized Operations of Decarbonized Chemical Plants with Renewable-driven Transmission Systems]] — децентрализованный фреймворм для совместной оптимизации энергосистем и химических заводов с изоляцией данных.
- [[https://arxiv.org/abs/2605.21115][Automated Byzantine-Resilient Clustered Decentralized Federated Learning for Battery Intelligence in Connected EVs]] — блокчейн-ориентированная система федеративного обучения для EV с защитой от византийских атак.

These look like sometime LLM returns a mailformed ORG file. These should be analyzed and fixed at the system prompt level. There errors are rare but happens (around 1 per 2weeks)

## Scope
- Extract the common mistakes
- Harden system prompt / org-mode instructions for LLM

  
## What Changes: Analyze and fix daily digest errors
Update system prompt based on the errors analysis.

## Approache "how" - Technical strategy, architectural decisions, and key implementation det
Analsys of common errors first, extracting them second, updating system prompt with what LLM should not do with example. Examples and system prompt updates should be limited: avoid directly putting this 1000 lines log into prompt.
