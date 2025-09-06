# Product Requirements Document: Developer-Centric Contextual RAG System

## Introduction

For modern AI assistants to provide relevant, accurate answers in specialized domains, they must be augmented with external knowledge beyond their base training[anthropic.com](https://www.anthropic.com/news/contextual-retrieval#:~:text=For%20an%20AI%20model%20to,vast%20array%20of%20past%20cases). Retrieval-Augmented Generation (RAG) addresses this by retrieving relevant documents and appending them to the prompt, but traditional RAG approaches often lose important context during chunking and encoding[anthropic.com](https://www.anthropic.com/news/contextual-retrieval#:~:text=Generation%20%28RAG%29,information%20from%20the%20knowledge%20base). This PRD proposes a **developer-centric, containerized Contextual RAG system** that overcomes those limitations using **Contextual Retrieval** techniques[anthropic.com](https://www.anthropic.com/news/contextual-retrieval#:~:text=In%20this%20post%2C%20we%20outline,better%20performance%20in%20downstream%20tasks) and a hybrid memory architecture. The system will combine semantic vector search with knowledge graph traversal to dramatically improve retrieval accuracy and multi-hop reasoning. It will also incorporate a persistent memory layer (via the Model Context Protocol, MCP) to track knowledge and corrections over time, ensuring the AI assistant learns from feedback instead of repeating mistakes. The solution targets developers who need a privacy-friendly, extensible RAG platform that integrates with local LLMs and popular cloud models alike.

## Objectives and Goals

- **Seamless LLM Integration (Local & Cloud):** The system must support pluggable large language models, including local open-source LLMs (served via Ollama) and cloud-hosted models (OpenAI GPT-4/GPT-5, Anthropic Claude Sonnet/Opus, Google Gemini). Developers can easily switch or add models through configuration, enabling queries to be routed to a preferred model or ensemble. This ensures both offline capability and access to state-of-the-art model APIs as needed.
    
- **High-Performance Local Embeddings:** Leverage open-source embedding models (runnable locally) to generate vector representations of documents for semantic search. Preferred models include **Microsoft E5**, **BGE (BAAI’s bilingual model)**, and **InstructorXL**, which are state-of-the-art in multilingual embedding quality[medium.com](https://medium.com/@lars.chr.wiik/best-embedding-model-openai-cohere-google-e5-bge-931bfa1962dc#:~:text=Microsoft%20has%20taken%20a%20unique,M3). These models provide enterprise-grade semantic representations without API costs or data leakage. The embedding service should be optimized for performance (using GPU acceleration if available, or quantized CPU inference) and easily extensible to swap models.
    
- **Multi-Format Content Ingestion:** Provide an ingestion pipeline that can consume diverse data sources: PDF, Word, EPUB, Markdown, and text files, as well as websites (including behind authentication). This pipeline will extract raw text from files (using libraries like Apache Tika or Unstructured) and crawl web pages (using a headless browser like Playwright for dynamic content or login flows). It must handle batch uploads and scheduling for periodic recrawling if needed. The ingestion process includes document parsing, cleaning, and **intelligent text chunking** (e.g. using a recursive text splitter) to break content into manageable pieces while preserving context. All common document formats should be supported out-of-the-box (PDF, Office docs, HTML, etc.)[elephas.app](https://elephas.app/blog/best-embedding-models#:~:text=,with%20API%20keys%20of%20OpenAI).
    
- **Contextual Chunk Embeddings:** Implement **Contextual Embeddings** during indexing to preserve each chunk’s context and improve retrieval. For every text chunk, the system will generate a concise chunk-specific summary or preface (using an LLM prompt) that situates the chunk within the source document[anthropic.com](https://www.anthropic.com/news/contextual-retrieval#:~:text=concise%2C%20chunk,generate%20context%20for%20each%20chunk)[anthropic.com](https://www.anthropic.com/news/contextual-retrieval#:~:text=Copy). This contextual prefix is prepended to the chunk’s text before embedding and before building any lexical index, per Anthropic’s method[anthropic.com](https://www.anthropic.com/news/contextual-retrieval#:~:text=Contextual%20Retrieval%20solves%20this%20problem,%E2%80%9CContextual%20BM25%E2%80%9D)[anthropic.com](https://www.anthropic.com/news/contextual-retrieval#:~:text=The%20resulting%20contextual%20text%2C%20usually,before%20creating%20the%20BM25%20index). By giving each chunk knowledge of its document (“This chunk is from X about Y…”), we reduce ambiguity and dramatically increase the chance of retrieving the right information later. Anthropic reports that such **Contextual Retrieval** techniques can nearly halve the rate of missing relevant info during search[anthropic.com](https://www.anthropic.com/news/contextual-retrieval#:~:text=Our%20experiments%20showed%20that%3A).
    
- **Hybrid Vector & Graph Knowledge Base:** Use a dual **memory store** combining a vector database and a graph database to enable hybrid retrieval and knowledge linking. All chunks and documents will be stored with their embeddings in a **vector DB** (e.g. Chroma or Weaviate) for semantic similarity search. In parallel, key facts, entities, and relationships extracted from the data will be stored as nodes and edges in a **graph DB** (e.g. Neo4j) to capture the knowledge graph. This hybrid approach allows both “fuzzy” semantic matches and precise relational reasoning: the vector store maximizes recall of relevant info, while the knowledge graph provides rich context about how pieces of information connect[qdrant.tech](https://qdrant.tech/documentation/examples/graphrag-qdrant-neo4j/#:~:text=Advantages%20of%20Qdrant%20%2B%20Neo4j,GraphRAG)[cognee.ai](https://www.cognee.ai/blog/deep-dives/model-context-protocol-cognee-llm-memory-made-simple#:~:text=Cognee%20builds%20on%20these%20concepts,data%20structure%20alone%20might%20miss). The system will automatically create graph links between related chunks (e.g. shared entities or references) and between chunks and their source documents or summary nodes. By **“smart linking”** concepts across the corpus, the assistant can follow chains of facts to answer complex multi-hop questions that baseline RAG would miss[medium.com](https://medium.com/@zilliz_learn/graphrag-explained-enhancing-rag-with-knowledge-graphs-3312065f99e1#:~:text=While%20this%20approach%20works%20well,connecting%20disparate%20pieces%20of%20information)[medium.com](https://medium.com/@zilliz_learn/graphrag-explained-enhancing-rag-with-knowledge-graphs-3312065f99e1#:~:text=To%20address%20such%20challenges%2C%20Microsoft,with%20the%20Milvus%20vector%20database).
    
- **Contextual BM25 and Keyword Search:** In addition to dense vector search, the system will support exact keyword matching using a BM25 index built on the contextualized chunks. This is critical for queries involving proper nouns, error codes, or specific phrases that embeddings might not capture[anthropic.com](https://www.anthropic.com/news/contextual-retrieval#:~:text=While%20embedding%20models%20excel%20at,unique%20identifiers%20or%20technical%20terms)[anthropic.com](https://www.anthropic.com/news/contextual-retrieval#:~:text=Here%E2%80%99s%20how%20BM25%20can%20succeed,to%20identify%20the%20relevant%20documentation). The plan is to either integrate a lightweight textual search engine (such as an ElasticSearch/OpenSearch service or Weaviate’s built-in BM25 feature) to retrieve top N chunks by lexical similarity, or utilize the graph store for storing text and enabling full-text index on node properties. These **lexical results** will be combined with vector results for every query. Using rank fusion techniques (e.g. Reciprocal Rank Fusion), the system will merge the two result sets into a single relevance-ranked list[anthropic.com](https://www.anthropic.com/news/contextual-retrieval#:~:text=1,prompt%20to%20generate%20the%20response). This hybrid retrieval ensures that both semantically relevant and keyword-exact matches are considered, significantly improving coverage of relevant knowledge.
    
- **Reciprocal Rank Fusion (RRF) for Combined Search:** The retrieval module will implement a fusion algorithm to merge results from the vector search (semantic) and graph/keyword search (symbolic). For example, we will apply RRF scoring: if a document is highly ranked in both the vector similarity search and the BM25/graph search, it will surface to the top of the combined results. This approach balances precise term matching with broader semantic context[anthropic.com](https://www.anthropic.com/news/contextual-retrieval#:~:text=1,prompt%20to%20generate%20the%20response)[python.langchain.com](https://python.langchain.com/docs/integrations/vectorstores/weaviate/#:~:text=A%20hybrid%20search%20combines%20a,allows%20you%20to%20pass). The top-$K$ retrieved chunks (e.g. top 10–20) from the fused ranking will be passed to the LLM as context. (We will also evaluate using an optional **reranker** model – such as a cross-encoder or instruction-following LLM – to re-score the candidate chunks for relevance, as Anthropic did to achieve a further ~67% reduction in missed info[anthropic.com](https://www.anthropic.com/news/contextual-retrieval#:~:text=failed%20retrievals%20by%2049,better%20performance%20in%20downstream%20tasks).)
    
- **Knowledge Graph Linking & Memory Reconstruction:** The graph database will not only store static relationships from documents, but also serve as a dynamic **memory graph**. As content is ingested, the system will use an LLM or NLP pipeline to extract entities and relations from each chunk (e.g. person X works for company Y, or concept A relates to concept B)[medium.com](https://medium.com/@zilliz_learn/graphrag-explained-enhancing-rag-with-knowledge-graphs-3312065f99e1#:~:text=1,construct%20an%20initial%20knowledge%20graph). These will form a knowledge graph where nodes represent key entities or concepts (and possibly documents or summaries), and edges represent relationships (e.g. “is CEO of”, “cites”, “corrects”, etc.). This graph can be traversed at query time to find indirect connections between a user’s question and stored knowledge. For example, if a question involves two disparate concepts, the graph may reveal a path linking them, allowing the system to retrieve intermediate context. The graph memory also enables **memory reconstruction** – if the assistant needs to clarify context or recall how a correction was made, it can follow the links (like a chain of reasoning or a revision history). Overall, the graph enhances the assistant’s ability to **reason about context** by following relationships rather than relying only on similarity.
    
- **Persistent Memory via MCP (Model Context Protocol):** Implement an **MCP-compatible memory system** that allows the assistant to store and retrieve information across sessions. The Model Context Protocol (an open standard by Anthropic) provides a JSON-RPC based interface for LLMs to access external tools and context in a standardized way[medium.com](https://medium.com/@nimritakoul01/the-model-context-protocol-mcp-a-complete-tutorial-a3abe8a7f4ef#:~:text=,Build%20composable%20integrations%20and%20workflows)[medium.com](https://medium.com/@nimritakoul01/the-model-context-protocol-mcp-a-complete-tutorial-a3abe8a7f4ef#:~:text=Model%20Context%20Protocol%20,problem%20of%20fragmented%20data%20access). Our system will include a **Memory MCP server** that the LLM can query for additional context or corrections on-the-fly. This memory will store: (a) **Full documents and chunks** (for retrieval), (b) **Summaries** of documents or discussions (for quick reference), and (c) **Correction entries** that record when the model was corrected on a fact. The memory server exposes operations like: `add_memory` (store a piece of info with tags/metadata), `search_memory` (semantic lookup), `get_memory` (by key or ID), `link_memories` (create a relationship between two memory items), and deletion or expiration of memories[lobehub.com](https://lobehub.com/mcp/hridaya423-memory-mcp#:~:text=support%20for%20tags%2C%20timestamps%2C%20and,based%20on%20links%20and%20relationships)[lobehub.com](https://lobehub.com/mcp/hridaya423-memory-mcp#:~:text=,with%20a%20specified%20relationship%20type). These functions will be accessible to the LLM agent (as tools) and also via the UI, enabling both automated and manual memory management.
    
- **Correction Tracking and Injection:** A special focus is maintaining a **correction log** so the system learns from mistakes. When the assistant provides an incorrect answer and is given the correct information (by a user or developer), the system will record that as a correction memory, linking it to the relevant topic or question. For example, if the model mistakenly stated a wrong year for an event, the correction (“Event X happened in 2020, not 2021”) is stored and linked to _Event X_. The next time a query involves that event, the memory tool can proactively surface the correction to the LLM (ensuring it uses the updated fact). These correction entries will be tagged and easily searchable. The system supports operations to **“forget”** outdated or irrelevant information (removing it from active memory), **“pin”** crucial facts so they are always included or have high priority during retrieval, and **“inject” corrections** when similar contexts arise. By tracking patterns of errors and fixes, the memory can even help prevent repeated mistakes – akin to the Claude Code memory server’s ability to learn from past errors[lobehub.com](https://lobehub.com/mcp/viralvoodoo-claude-code-memory#:~:text=Advanced%20Intelligence). All of this is done with minimal token overhead by keeping the majority of memory off-prompt: the LLM can fetch it via the MCP interface only when needed, rather than carrying a huge conversation history. This yields a more **efficient long-term memory** with virtually unlimited capacity but on-demand recall[mem0.ai](https://mem0.ai/blog/how-to-make-your-clients-more-context-aware-with-openmemory-mcp#:~:text=In%20the%20rapidly%20evolving%20landscape,they%20forget%20everything%20between%20sessions)[mem0.ai](https://mem0.ai/blog/how-to-make-your-clients-more-context-aware-with-openmemory-mcp#:~:text=,delete_all_memories).
    
- **Phoenix Backend UI & Monitoring:** Provide a developer-friendly **web UI built with Phoenix (Elixir)** for managing the system. Phoenix will serve a responsive dashboard for: ingesting data (file uploads, entering site URLs with credentials for crawling), monitoring ingestion jobs, browsing and searching the knowledge base, and visualizing the knowledge graph. Users should be able to see what documents are in the vector store, inspect nodes and relationships in the graph (with an interactive graph view), and view the list of memory entries (with their tags and links). The UI will also expose controls to **pin/forget memory items** or manually correct stored facts. Correction visualizations might show a before/after of an answer or highlight parts of the knowledge graph that were updated. Additionally, the Phoenix UI will allow initiating chat sessions with the LLM and viewing the retrieved context chunks (for transparency). It will show, for each assistant answer, which documents or memory items were used (and whether any correction was applied), so developers can trust and verify the sources. Phoenix is chosen for its ability to handle real-time updates (using LiveView or channels) – e.g. streaming LLM responses, live crawling progress, or updates when new knowledge is added – providing a smooth interactive experience. The backend will be structured as an Elixir application that communicates with the RAG core services (vector DB, graph DB, etc.) via HTTP or library clients, making it easy to integrate into existing Elixir systems if needed.
    

## System Architecture Overview

The system comprises multiple containerized components orchestrated together, following a modular microservice design. The high-level architecture is illustrated below:

 

_Example architecture for a hybrid RAG system combining data ingestion, vector database, graph database, and LLM serving. The ingestion flow (left) processes files and websites into a vector index and knowledge graph. The query flow (right) shows the LLM agent retrieving relevant graph nodes and vectors, fusing results, and generating an answer with supporting context._

 

At a glance, the architecture is divided into two subsystems: **Data Ingestion** and **Query Serving**[cloud.google.com](https://cloud.google.com/architecture/gen-ai-graphrag-spanner#:~:text=Architecture). The data ingestion side handles importing and preprocessing knowledge into the vector and graph stores. The serving side handles user queries by retrieving from those stores and interacting with the LLMs. Key components and their interactions are as follows:

### 1. Data Ingestion Pipeline

- **Ingestion Service (Parser & Indexer):** A container (likely Python-based) responsible for document ingestion workflows. It provides an API or task queue that the UI can call to submit new documents or crawl jobs. For file inputs, this service uses parsers to extract raw text (e.g. PDF -> text via PDFPlumber or PyMuPDF, DOCX via python-docx, etc.). For HTML/website inputs, it uses a headless browser automation (Playwright or Selenium) to log in (if credentials provided) and fetch page content, then cleans it to text (e.g. using BeautifulSoup or Unstructured). The text is then chunked into semantically coherent pieces (configurable chunk size with overlaps to preserve context boundaries). Next, for each chunk, the service calls an **Embedding Model** (which could be a local inference server or library call) to compute a vector embedding. It also calls a **Contextualizer LLM** (which could be a local LLM or a fast cloud model) with a prompt to generate the chunk’s contextual summary[anthropic.com](https://www.anthropic.com/news/contextual-retrieval#:~:text=concise%2C%20chunk,generate%20context%20for%20each%20chunk)[anthropic.com](https://www.anthropic.com/news/contextual-retrieval#:~:text=Copy). The chunk is then stored in the **Vector Database** with fields for the text, embedding, source document, and the generated context text (which is also indexed for BM25). Simultaneously, the service extracts structured data for the **Graph Database**: using either an NLP pipeline (NER and relation extraction) or an LLM (with a prompt to list entities/relations in the chunk)[medium.com](https://medium.com/@zilliz_learn/graphrag-explained-enhancing-rag-with-knowledge-graphs-3312065f99e1#:~:text=1,construct%20an%20initial%20knowledge%20graph). It writes nodes for key entities (or reuses existing nodes if they already exist in the graph) and edges for relationships between entities. It also creates “document” nodes and links chunk nodes to their parent document and section hierarchy (enabling provenance tracking). The result of ingestion is that the chunk content is indexed in two ways: by semantic vector and by graph connections (and optionally a lexical index for full-text search).
    
- **Vector Database:** A dedicated service for high-dimensional similarity search. We choose an open-source vector DB like **ChromaDB** or **Weaviate**. ChromaDB can be embedded in the ingestion service process or run as a separate container; in our design we treat it as a separate persistent service with a gRPC/HTTP interface. Each chunk is upserted into the vector DB with its embedding and metadata (document ID, chunk index, etc.). Weaviate is an alternative that offers built-in hybrid search (vector + keyword) out-of-the-box[weaviate.io](https://weaviate.io/blog/hybrid-search-for-web-developers#:~:text=Hybrid%20search%20in%20Weaviate%20combines,term%20matching%20and%20semantic%20context)[python.langchain.com](https://python.langchain.com/docs/integrations/vectorstores/weaviate/#:~:text=A%20hybrid%20search%20combines%20a,allows%20you%20to%20pass). If Weaviate is used, we will leverage its capability to perform combined similarity+BM25 queries in one go. If using Chroma, we might maintain a parallel text index for BM25 (either via an integrated library or by using a search engine like ElasticSearch). The vector DB is optimized for fast $k$-NN queries and can scale to millions of embeddings if needed.
    
- **Graph Database:** A Neo4j container (open-source Community edition) will store the knowledge graph. Ingestion writes to Neo4j using Cypher queries or via a Python Neo4j client. The graph schema will include node types like `Document`, `Chunk`, and various entity types (e.g. `Person`, `Organization`, `Concept`), as well as relationship types (e.g. `MENTIONS`, `CITES`, `BELONGS_TO`, or more domain-specific ones). For example, if a chunk of text says “Alice (CEO of Acme Corp) introduced product X in 2023,” the ingestion might create: a `Person` node "Alice", an `Organization` node "Acme Corp", with an edge `IS_CEO_OF` between them, a `Product` node "Product X" with `INTRODUCED_BY` edge from Alice, and a temporal or event node for "Product Launch 2023". The chunk itself would be a node linked to "Alice", "Acme Corp", "Product X" via `MENTIONS` edges. This explicit graph of relationships supplements the implicit knowledge in the text. Neo4j will also store links for **corrections and memory**: e.g. a `Correction` node might be linked to the fact it corrects with a `CORRECTS` relationship. The graph DB thus serves both as a knowledge graph and a long-term memory graph.
    

### 2. Query and Retrieval Flow

- **User Query Interface:** Users (or client applications) will interact with the system via the Phoenix web UI or an API endpoint. When a user submits a question, they can optionally specify which LLM to use (or use a default routing policy). The query (and any relevant session info like conversation history or user profile if available) is sent to the **LLM Orchestrator** component.
    
- **LLM Orchestrator / Agent:** This is the component (possibly part of the Phoenix backend or a separate service) that orchestrates the prompt assembly and tool use for the LLM. It receives the raw user query and initiates a **retrieval step** before calling the LLM for final answer generation. The orchestrator will first vectorize the user query using the same embedding model used for documents (ensuring we’re in the same embedding space). With the query embedding, it performs a similarity search in the **Vector DB** to fetch the top $N$ most relevant chunks (e.g. $N=10$). In parallel, it performs a **keyword/BM25 search** (if the query contains any rare keywords or phrases) to fetch additional relevant chunks by lexical match[anthropic.com](https://www.anthropic.com/news/contextual-retrieval#:~:text=While%20embedding%20models%20excel%20at,unique%20identifiers%20or%20technical%20terms)[anthropic.com](https://www.anthropic.com/news/contextual-retrieval#:~:text=Here%E2%80%99s%20how%20BM25%20can%20succeed,to%20identify%20the%20relevant%20documentation). It also queries the **Graph DB**: this can happen in two ways – (a) **Direct concept search:** use the query terms to find matching nodes (e.g. if a person or term in the query exactly matches a node name) and retrieve their neighboring nodes/chunks; and/or (b) **Semantic traversal:** use the vector results to identify which document or entity nodes they relate to, then traverse the graph around those to find connected info. For instance, if the vector search pulls a chunk about “Project Alpha, led by Alice”, the system might traverse the graph for other chunks linked to Alice or Project Alpha (perhaps retrieving background info like “Alice is CEO of Acme Corp”) that could provide helpful context. The orchestrator then **fuses these results** – combining the sets from vector similarity, BM25, and graph traversal, applying a rank fusion algorithm to prioritize documents that appear across methods[anthropic.com](https://www.anthropic.com/news/contextual-retrieval#:~:text=1,prompt%20to%20generate%20the%20response). Duplicates are removed (ensuring we don’t feed the same content twice). The top $K$ unique chunks/nodes (configurable, e.g. 10 or 20) are selected as the retrieval context. Optionally, a reranker model may be applied here to fine-tune the selection, using a small language model or cross-encoder to score each chunk’s relevance to the query more precisely[anthropic.com](https://www.anthropic.com/news/contextual-retrieval#:~:text=Further%20boosting%20performance%20with%20Reranking)[anthropic.com](https://www.anthropic.com/news/contextual-retrieval#:~:text=1,to%20generate%20the%20final%20result).
    
- **MCP Memory Lookup:** Before finalizing the prompt, the orchestrator will also check the **MCP Memory** for any relevant stored data. It will use the MCP client interface to call `search_memory` with the user query (or related keys) against the memory server. Because the memory server itself can use a vector store under the hood (e.g. Qdrant or Chroma)[mem0.ai](https://mem0.ai/blog/how-to-make-your-clients-more-context-aware-with-openmemory-mcp#:~:text=,delete_all_memories)[mem0.ai](https://mem0.ai/blog/how-to-make-your-clients-more-context-aware-with-openmemory-mcp#:~:text=,vector%20store%20under%20the%20hood), it can return any saved notes or corrections that semantically match the query. For example, if the question is about “Acme Corp Q2 2023 revenue” and we previously stored a correction or summary about that, the memory search will retrieve it. The orchestrator can then inject this **memory snippet** into the prompt (with a tag like “Note: ...”) or include it in the retrieved context with high priority. Additionally, if any **pinned facts** are relevant (always-include knowledge, like key company info), those will be prepended to the context. The memory lookup ensures the LLM is aware of any **user-provided corrections or updates** relevant to the query.
    
- **Prompt Assembly:** The orchestrator now assembles the prompt for the LLM. It will typically include a system instruction (defining the assistant’s role and any formatting requirements), the user’s query, and a section for context. In that context section, the top-$K$ retrieved documents/chunks and any memory items are included. Each context item may be prefaced with a source title or other metadata for clarity. We will ensure the prompt clearly delineates what is user query vs. what is context (to avoid the model getting confused), per best practices. The prompt might look like: _"...\nHere are relevant excerpts:\n[1] {chunk text}\n[2] {chunk text}\n...\nUsing this information, answer the question..."_. If multiple context chunks came from the same document, we might group or compress them for efficiency. At this point, the orchestrator calls the chosen **LLM model** (either via Ollama for local models or via API for cloud models) with the assembled prompt. If using an agent loop (for tool usage), the LLM might iteratively call back to the memory tool – for instance, if during generation it realizes it needs more info, it could invoke a memory search for a follow-up concept. Our design will allow such interactive tool use via the MCP interface, but in many cases a single-step retrieval + answer generation will suffice.
    
- **Answer Generation:** The LLM generates a response based on the prompt and provided context. Because the relevant information was retrieved and given in-context, the LLM’s answer should be grounded in the source material. The system will encourage the model to cite source indices (e.g. “[1]”) in its answer when applicable, to increase transparency. After the model produces the final answer, the orchestrator can post-process it to format citations properly (ensuring they map to the sources). The answer is then streamed back to the user in the UI. We will also log the query and which sources were used. If the user corrects the answer or provides feedback, the system can create a new **Correction memory** linking the query to the correct info, as described earlier. Over time, these interactions enrich the memory graph (the assistant effectively learns through usage).
    

### 3. Memory & Feedback Loop

- **Memory MCP Server:** This component runs as a service that implements the MCP protocol, managing the long-term memory. We can base this on existing open-source MCP memory servers (for example, one by LobeHub uses Neo4j for memory relationships[lobehub.com](https://lobehub.com/mcp/viralvoodoo-claude-code-memory#:~:text=This%20MCP%20server%20creates%20a,development%20concepts%2C%20solutions%2C%20and%20workflows), and another “OpenMemory” uses Postgres+Qdrant[mem0.ai](https://mem0.ai/blog/how-to-make-your-clients-more-context-aware-with-openmemory-mcp#:~:text=,vector%20store%20under%20the%20hood)). Our memory server will be configured to use the **same vector DB and graph DB** as the rest of the system (or their own dedicated instances if isolation is preferred). This way, all data lives in unified stores but is accessible via the MCP interface. The memory server will maintain an index of memory objects (each with an ID, content, tags, timestamps) and support linking memories to each other[lobehub.com](https://lobehub.com/mcp/hridaya423-memory-mcp#:~:text=stored%20memories%20,based%20on%20links%20and%20relationships). For instance, a summary memory might link to the full document memory it summarizes, a correction memory links to the fact it corrects, etc. The **MCP client (the LLM)** connects to this server (over localhost network, likely via Server-Sent Events as per MCP spec)[medium.com](https://medium.com/@nimritakoul01/the-model-context-protocol-mcp-a-complete-tutorial-a3abe8a7f4ef#:~:text=The%20protocol%20uses%20JSON,messages%20to%20establish%20communication%20between) and can invoke methods. We will implement custom logic for `forget` (which might just tag an item as deprecated or remove it from indexes) and `pin` (which could internally mark an item such that `search_memory` always returns it for certain queries or always includes it in prompts). The **Phoenix UI** will provide a front-end to these operations: for example, listing all memories with their tags and allowing the user to click “Forget” or “Pin” on each, which under the hood calls a backend API that interacts with the memory server (or directly sets flags in the DB). We will also present **correction visualization** here: showing a list of all corrections made, with the ability to edit or remove them.
    
- **Knowledge Graph Browser:** Because the memory and knowledge graph are one and the same in Neo4j, the UI can present a visualization of the graph. Developers can inspect how information is connected – e.g. clicking on an entity to see all documents and facts related to it. This is extremely useful for debugging why the assistant answered a certain way or for discovering hidden relationships in the data. The graph view can also highlight where corrections have been applied (perhaps with a special edge type or color for “CORRECTS” relationships between nodes). Users can traverse the graph manually, which complements the automated traversal the agent does. Essentially, this system doesn’t just produce answers – it also serves as a **interactive knowledge base** for developers.
    

## Technical Stack and Tooling Choices

**Large Language Models:** For local inference, we will use **Ollama** to run and manage open-source LLMs. Ollama provides a containerized way to serve models like LLaMA 2, Code Llama, Mistral, etc., and even embedding-specific models, with a simple API. This lets developers run the assistant entirely offline if needed. The PRD assumes GPT-4/5 and Claude will be accessible via their APIs for comparison or when higher quality is needed. By abstracting the LLM interface, we allow easy addition of new model backends (e.g. integrating with AWS Bedrock or Azure OpenAI if required in enterprise settings). The system can be configured to use a specific model per query or route certain types of queries to specialized models (for instance, code-related questions to Code Llama or Claude-Opus).

 

**Embedding Models:** We recommend using **E5 (Large)** as the default embedding model due to its strong performance on diverse retrieval benchmarks and its multilingual support[medium.com](https://medium.com/@lars.chr.wiik/best-embedding-model-openai-cohere-google-e5-bge-931bfa1962dc#:~:text=Microsoft%20has%20taken%20a%20unique,M3). E5 is open-sourced by Microsoft and can be run locally with the Hugging Face transformers library. For even faster or domain-tuned embeddings, alternatives include **BGE** (especially if Chinese or other language support is needed) and **InstructorXL** (which can produce task-specific embeddings by prepending instructions). All these models are open-source and **perform competitively with proprietary embeddings**. For instance, E5 and BGE are among top performers on the MTEB embedding leaderboard, on par with OpenAI’s text-embedding models, but without usage fees. The embedding computation will be done within the ingestion service – utilizing either the CPU (with optimizations like FAISS or BLAS for matrix ops) or GPU if available for faster throughput. We also note that **Ollama** can potentially host certain embedding models in GGML format[elephas.app](https://elephas.app/blog/best-embedding-models#:~:text=Ollama); however, many embedding models are encoder-style (BERT-like) not GPT-like, so the primary approach is to use a Python embedding library. The embedding vectors will be of dimensionality 768 to 1024 (depending on model) and stored in the vector DB.

 

**Vector Database:** For ease of use and local deployment, **ChromaDB** is a strong choice (it’s lightweight, Python-native, and can persist to disk). Chroma will store the chunk embeddings and support similarity search with cosine distance. It also supports filtering by metadata (so we can, for example, restrict search to certain document sources or date ranges if needed in future). Alternatively, **Weaviate** is an attractive option if we desire built-in hybrid search; Weaviate’s hybrid query can combine BM25 and vector scores internally[weaviate.io](https://weaviate.io/blog/hybrid-search-for-web-developers#:~:text=Hybrid%20search%20in%20Weaviate%20combines,term%20matching%20and%20semantic%20context). Weaviate is heavier (runs as its own service with a Rust core and optional dependencies), but it could replace the need for a separate lexical index. Weaviate also scales well and can be used in a cluster, which might be beneficial if our dataset grows large. For now, the PRD will proceed with Chroma for simplicity, and consider Weaviate as a swappable module. Both are open-source. (We avoid proprietary vector SaaS like Pinecone unless absolutely required, but the system’s design would allow using Pinecone’s API too if configured, thanks to modular data access layers).

 

**Graph Database:** **Neo4j** is chosen due to its mature ecosystem (Cypher query language, robust performance, and community tools). As an ACID-compliant graph store, it ensures our knowledge graph can be queried reliably and updated with relationships as needed. Neo4j Community Edition (open-source) will be used; it can run as a single Docker container with a mounted volume for persistence. The choice of Neo4j is reinforced by prior art: some MCP memory servers already use Neo4j to great effect for mapping complex relationships and enabling graph queries from LLMs[lobehub.com](https://lobehub.com/mcp/viralvoodoo-claude-code-memory#:~:text=This%20MCP%20server%20creates%20a,development%20concepts%2C%20solutions%2C%20and%20workflows)[lobehub.com](https://lobehub.com/mcp/viralvoodoo-claude-code-memory#:~:text=%2A%20Relationship%20Mapping%20,specific%20memory%20retrieval). Neo4j also recently introduced vector indexing in its Graph Data Science library, opening the door to store embeddings in the graph, though in our architecture we keep vector search in a specialized DB for now (for performance). We will use Neo4j primarily for the structured parts – linking entities and tracking memory metadata – and rely on the vector DB for raw text similarity. **Alternate options:** If a lighter graph is desired, we could consider **Memgraph** (an in-memory graph DB that speaks a similar query language) or even a simpler approach like storing relationships in a document store. However, the expressive querying and visualization tools of Neo4j are valuable for development and debugging.

 

**Document Parsing & Crawling:** To handle various file formats, we will use a combination of libraries: `pdfplumber` or `PyMuPDF` for PDFs, `python-docx` for Word, `ebooklib` or `calibre` for EPUB, `markdown` for MD, and plain text for .txt. We can also integrate **Unstructured.io** pipelines which provide universal document parsing into clean text with minimal boilerplate. For HTML and web content, **Playwright** is our tool of choice for crawling – it can headlessly open pages, fill login forms, navigate, and retrieve the final rendered HTML. We will build a wrapper that accepts user credentials or cookies for sites as needed (ensuring these secrets are handled securely). After getting the page HTML, we’ll extract main content (perhaps using readability algorithms or Unstructured’s HTML loader). The crawling component will respect robots.txt and have rate limiting to avoid overload. In case of API-accessible content (like a REST API for a knowledge base), developers can extend the ingestion to pull data via API as well. We emphasize using **open-source** libraries for all ingestion steps so the pipeline can run in isolated environments with no external dependencies.

 

**Hybrid Search Implementation:** If using ChromaDB (which lacks direct BM25), we will integrate a Python-based BM25 solution. One approach is indexing all chunk text in an **OpenSearch** instance (open-source ElasticSearch fork) and querying it for top-$N$ chunks by BM25 score. However, to avoid the overhead of another service, we might use a simpler library like `rank-bm25` or Whoosh for an in-memory index of chunks that can be periodically updated. Given our data volume is manageable, this is feasible. The retrieval orchestrator will then call both the Chroma and the BM25 index. If using Weaviate, the hybrid is simpler (one query with a vector and it returns combined results). We will implement **Reciprocal Rank Fusion** manually: e.g. for each result from vector search and each from BM25, assign a score like `1/(rank)`, then combine by matching IDs, summing scores, etc.[anthropic.com](https://www.anthropic.com/news/contextual-retrieval#:~:text=3,prompt%20to%20generate%20the%20response). This can be done quickly in memory since $N$ is small (tens of results). The fused list is then sorted by combined score. This approach has been shown to be very effective in information retrieval to balance different retrieval methods without complex training[anthropic.com](https://www.anthropic.com/news/contextual-retrieval#:~:text=1,prompt%20to%20generate%20the%20response).

 

**Model Context Protocol (MCP):** To implement MCP, we will use the official **Anthropic MCP Python SDK**[medium.com](https://medium.com/@nimritakoul01/the-model-context-protocol-mcp-a-complete-tutorial-a3abe8a7f4ef#:~:text=It%20is%20developed%20by%20Mahesh,Python%20SDK%20and%20TypeScript%20SDK) to create our memory server. This SDK handles the JSON-RPC messaging and SSE streaming so we can focus on defining the server-side methods (`add_memory`, `search_memory`, etc.). We’ll integrate our vector and graph operations inside these methods. For example, `search_memory(query)` will perform a vector similarity search in Chroma (or query the Neo4j if we allow text search on memory content stored there) and return the top matches. We’ll extend the memory server’s data model to include the linking and tagging features we need (in practice, this might simply leverage Neo4j’s data; e.g. a memory object’s attributes and relationships are stored as a node and relationships in Neo4j, so a `link_memories(A,B,type)` RPC call just creates a relationship in the graph DB)[lobehub.com](https://lobehub.com/mcp/hridaya423-memory-mcp#:~:text=,with%20a%20specified%20relationship%20type). Because MCP is designed to be **client-agnostic**, any future MCP-compatible client or agent could interface with our memory just by configuration. This means down the line, a VSCode extension or other tool could use the same memory store to assist with code (by connecting as an MCP client), illustrating the flexibility of the chosen approach.

 

**Phoenix Web Framework:** The UI will be built in **Elixir Phoenix** for robustness and real-time interactivity. We will develop a Phoenix application that serves a web dashboard for the system. Phoenix’s LiveView will allow us to push updates to the front-end when, say, a new document has finished ingestion (showing status) or when an answer is streaming from the LLM. Elixir is highly suitable for orchestrating between different services concurrently (using its lightweight processes), which fits our need to concurrently query vector DB, graph DB, memory, and LLMs. The Phoenix app will likely call out to the Python ingestion/index service via HTTP for operations like “ingest this file” or “ask this query” (unless we implement those parts directly in Elixir — but using Python’s ML libraries is easier, so a small REST API in the Python service is fine). We will expose internal REST or gRPC endpoints from the Python side (e.g. `/ingest`, `/query`), which Phoenix can consume. For the Neo4j graph, we can either call it from Python (during ingestion/query) or directly from Elixir using the Neo4j Bolt driver; both approaches are possible. In the interest of a clean separation, the Python service might handle all retrieval logic (calling both Chroma and Neo4j and fusing results) and return the final context to Phoenix. Phoenix then just forwards that context to the LLM (or instructs the Python service to do so and stream results back). We will decide on the exact split during implementation, but the **modularity** ensures that each piece (UI, retrieval core, databases, LLMs) can be developed and scaled independently.

 

**Open-Source Tools Summary:** To recap recommendations for specific needs:

- _Embedding Models:_ Microsoft **E5-large** (high-quality, multi-domain)[medium.com](https://medium.com/@lars.chr.wiik/best-embedding-model-openai-cohere-google-e5-bge-931bfa1962dc#:~:text=Microsoft%20has%20taken%20a%20unique,M3); BAAI **BGE-large** (great multilingual coverage, especially Chinese)[medium.com](https://medium.com/@lars.chr.wiik/best-embedding-model-openai-cohere-google-e5-bge-931bfa1962dc#:~:text=Microsoft%20has%20taken%20a%20unique,M3); **Instructor-XL** (for instruction-tuned embeddings). All available on Hugging Face. These can be converted to GGML if needed for Ollama, or run via the Transformers library.
    
- _Website Crawling:_ **Playwright** for headless browsing and login automation (open-source by Microsoft); for simpler sites, Python **requests + BeautifulSoup** (fast, lightweight). For structured web data, consider **Scrapy** if large-scale crawling is needed.
    
- _Graph Construction:_ **LangChain’s LLMGraphTransformer** can automate graph building from text using an LLM[cloud.google.com](https://cloud.google.com/architecture/gen-ai-graphrag-spanner#:~:text=3,or%20Document%20AI%27s%20Layout%20Parser)[cloud.google.com](https://cloud.google.com/architecture/gen-ai-graphrag-spanner#:~:text=7,graph%20nodes%20in%20Spanner%20Graph). We can use it to quickly bootstrap our knowledge graph (especially if using a powerful model like Claude or GPT-4 to extract relations). Another tool is **LlamaIndex KG** index, which similarly parses texts into a graph of entities. If not using those, a custom approach with spaCy for NER plus some rule-based relation extraction can be employed for specific domains.
    
- _Hybrid Search APIs:_ **Weaviate** (for integrated hybrid queries)[weaviate.io](https://weaviate.io/blog/hybrid-search-for-web-developers#:~:text=Hybrid%20search%20in%20Weaviate%20combines,term%20matching%20and%20semantic%20context); **LlamaIndex** or **LangChain retrievers** which provide abstractions to combine multiple searches (e.g. use a `VectorIndexRetriever` and a `BM25Retriever` and union results). Our approach of implementing RRF is straightforward and doesn’t depend on external APIs, ensuring control and transparency.
    
- _Memory/Correction Tracking:_ **Mem0 OpenMemory** is an open-source MCP memory server that already demonstrates minimal token overhead by keeping context in a local vector store[mem0.ai](https://mem0.ai/blog/how-to-make-your-clients-more-context-aware-with-openmemory-mcp#:~:text=,delete_all_memories). We can draw inspiration or even components from it (it uses Qdrant + Postgres; we can adapt to Chroma + Neo4j). Additionally, the **LobeHub Memory Server**[lobehub.com](https://lobehub.com/mcp/hridaya423-memory-mcp#:~:text=memories%2C%20and%20find%20related%20content,based%20on%20links%20and%20relationships) gives a template for features like tagging and inter-memory linking which we will incorporate. Both being open-source, we have reference implementations to guide our development of a tailored memory service that meets our specific needs (like “pin” and “correct” semantics).
    

## Implementation Plan

We propose an iterative implementation in three major phases, each resulting in a usable subset of the system, culminating in the full integrated platform:

### **Phase 1: Core RAG Engine Development**

**Goal:** Set up basic retrieval-augmented QA with local components.

- _Task 1.1:_ **Container & DB Setup** – Define the Docker Compose configuration for the core services. Spin up containers for Neo4j (with appropriate config and mounting for persistence) and the chosen vector DB (Chroma can be run in-process initially; if Weaviate, run its container). Verify that the databases are accessible (e.g. Neo4j Bolt/HTTP port, Weaviate API if used).
    
- _Task 1.2:_ **LLM Integration** – Deploy the Ollama container and load a representative local model (e.g. a 7B LLaMA2 or Mistral for testing). Write a wrapper in the orchestrator to send prompts to Ollama’s API and stream responses. Simultaneously, set up API credentials and client code for at least one cloud model (OpenAI API for GPT-4) to ensure the ability to switch. Abstract these behind a service interface (so switching is one config flag). Test by issuing a simple prompt to each to confirm connectivity.
    
- _Task 1.3:_ **Embedding Service** – Implement a Python module for generating embeddings using HuggingFace Transformers. Load the E5-base model initially (for faster iteration) and verify that given a sample text it returns a vector of expected dimension. If using Ollama for embeddings (via a model like `nomic-embed`), test that route as well. This module will later be integrated into ingestion, but we validate it standalone first.
    
- _Task 1.4:_ **Basic Ingestion Pipeline** – Build a minimal ingestion script that takes a plain text file, splits it (e.g. by paragraphs), generates embeddings for each chunk, and upserts them into the vector DB. Also, create an initial BM25 index (could be as simple as storing chunks in a list and using `rank_bm25` to verify the concept). Skip graph construction in this step. After ingesting a sample document, test a query by computing its embedding and finding the nearest chunks; ensure the retrieved text indeed contains the answer if query is answerable from the doc. This validates the end-to-end RAG on a small scale.
    
- _Task 1.5:_ **Contextual Embedding Prototype** – Write a prompt for chunk contextualization and use a hosted model (Claude or GPT-4) to generate a context prefix for a chunk. Evaluate qualitatively if the prefix adds useful information (document title, section, etc.). Incorporate this prefix in the embedding pipeline (store it as part of chunk text for BM25 and also prepend to text before embedding). Re-ingest the document with this technique and see if retrieval improves for any ambiguous queries. This will lay groundwork for automating this with local models or caching.
    
- _Milestone 1:_ A rudimentary RAG service running locally: developers can ingest a document via a script or API and query it, getting an answer from the local LLM with relevant context. This phase focuses on correctness of retrieval and integration of components, not yet scaling or UI.
    

### **Phase 2: Advanced Retrieval & Memory Features**

**Goal:** Enhance retrieval with graph-based reasoning and implement the persistent memory and correction system.

- _Task 2.1:_ **Knowledge Graph Construction** – Develop the mechanism to populate Neo4j with knowledge from documents. Start with a simple approach: for each chunk, use spaCy to extract named entities, create a node for each (if not exist), and create relationships like `MENTIONS` from Chunk->Entity. Also create a Document node and link all its chunk nodes to it (`HAS_CHUNK`). This yields a basic graph. Next, try using an LLM for one document: prompt it to list factual triples or relations. Parse the output and upsert those relations into Neo4j (creating custom relationship types as needed). Evaluate a few outputs to refine the prompt. Automate this so that for each chunk or each document, an LLM pass can add more edges (this might be slow, so possibly only do on demand or for key documents). Ensure the graph is indexable (add indexes in Neo4j on node names or types for performance).
    
- _Task 2.2:_ **Hybrid Retrieval Implementation** – Connect the orchestrator to actually query Neo4j. Implement a strategy: e.g., take the top 3 entity names from the user query (or from top vector chunks) and do a Cypher query to get nearby chunks/documents in the graph. Alternatively, query the graph for any chunk nodes whose text or metadata matches the query terms. This requires some experimentation. Once defined, integrate this query and merge results with the vector results. Write the rank fusion function to combine and sort them. Test with multi-hop question examples (you may craft a scenario where the answer is two hops away in the graph). Adjust weighting if needed (e.g. maybe give a slight boost to results that came via graph links).
    
- _Task 2.3:_ **MCP Memory Server** – Implement the memory server as a standalone process (could be a small Python FastAPI app or even use Node if leveraging an existing package). Start with basic functions: `add_memory(key, value, tags)`, `search_memory(query)` returning the top matches (use the same Chroma DB for vector search of memory items, or reuse the main one but maybe using a special collection for “memory” vs “document”). Use Neo4j to store memory relationships: e.g. a memory item can be a node with label `Memory` and have edges like `CORRECTS` or `RELATED_TO` to another node (which might be a Document or an Entity). Provide `link_memories(source, target, rel_type)` that creates an edge in Neo4j[lobehub.com](https://lobehub.com/mcp/hridaya423-memory-mcp#:~:text=,with%20a%20specified%20relationship%20type). Also implement `delete_memory(key)` (removing from both Chroma and Neo4j). The MCP protocol specifics (JSON-RPC over STDIO or SSE) can be handled by the Anthropic MCP SDK – essentially, define a class with those methods and run it. Test the memory server with a client (possibly using Claude Desktop or a small custom MCP client) to ensure it responds.
    
- _Task 2.4:_ **Integration of Memory in QA Loop** – Modify the query orchestrator to utilize the memory server. After initial retrieval, call `search_memory` with the query text. If results come back, decide how to include them. Perhaps always include the top 1-2 memory items at the top of the context (especially if they are corrections or pinned). Develop a policy: if a memory item has tag “pinned”, always include it; if tag “correction” and its content or metadata matches the query topic, include it with high priority. Also allow the LLM to actively use the memory: e.g., when generating, it could ask via MCP for something it realizes it needs (this is an advanced use-case; enabling it might simply require leaving the MCP connection open during the model’s generation loop). We will test a scenario where we “teach” the model a fact via memory and then ask about it to confirm it uses the memory (with the retrieval disabled to ensure it truly relied on memory).
    
- _Task 2.5:_ **Correction Workflow** – Implement how a correction is added: in the UI (to be built in phase 3) a user will mark an answer as wrong and input the correct info. But ahead of UI, we simulate it: e.g., create a small function `submit_correction(original_question, correct_answer)` that will store a memory item with content = correct_answer, tags = ["correction"], and link it to either the question context or the relevant entity node in the graph (e.g. if the question was about “Capital of X” and the correct answer is “Y”, link the memory to the entity node X in Neo4j). Now modify the search logic: when a new query comes in, if it involves entity X, we find if any correction memory linked to X exists – if yes, surface it (so the model won’t give the wrong answer again). This closes the feedback loop. We test by simulating a wrong answer, adding a correction, then asking again. If the model still errs, we adjust by maybe injecting a stronger prompt notice or directly using the memory content in the answer.
    
- _Milestone 2:_ At this stage, we have a back-end service that can ingest data into both vector and graph stores, retrieve context using a combination of semantic and graph search, incorporate long-term memory and apply stored corrections. The LLM can use these to answer queries more accurately. We can run a demo in a console or rudimentary interface to show: ingest docs, ask complex questions, correct the assistant, ask again. The system should demonstrate learning from the correction.
    

### **Phase 3: User Interface & Deployment**

**Goal:** Build the Phoenix UI and finalize containerization for a cohesive user experience.

- _Task 3.1:_ **Phoenix Backend and API** – Initialize a Phoenix (LiveView) project. Implement controllers or live views for major functions: a page for uploading documents (which calls the ingestion service API), a page for entering crawl URLs (calls a Phoenix endpoint that triggers the Python crawler and returns when done), a main chat interface for asking questions (this will call our orchestrator’s query API and stream results). Set up Phoenix channels or LiveView for streaming LLM responses token-by-token. Also implement endpoints that the Python services can call back to Phoenix if needed (e.g. a webhook to notify that a long ingestion job completed, which Phoenix can use to update the UI). Ensure CORS or networking between Phoenix and the other containers is configured (in Docker Compose, they share a network so can refer to service names).
    
- _Task 3.2:_ **Frontend Components** – Design a clean UI layout: e.g., a sidebar with list of documents/knowledge sources, main panel with chat or search. Use LiveView for reactivity: when a user uploads a file, show progress (perhaps by polling the ingestion status or by receiving events from the ingestion service if it can send them). For the Knowledge Graph visualization: integrate a JS library like **vis.js**, **D3**, or **Neo4j Bloom** (if license permits Community usage) to render the graph. We can provide an endpoint in Phoenix that queries Neo4j for a subgraph (e.g. around a selected node) and returns JSON, which the frontend JS then displays. This allows the developer to click through nodes. Similarly, for memory entries, a simple table/list UI with actions (pin/forget) can be done; upon clicking pin, Phoenix calls the memory server (via HTTP RPC or through our orchestrator’s API) to mark it. Use Phoenix LiveView bindings to immediately reflect the changes (e.g., an icon changes to show pinned). The chat interface will display the conversation and allow corrections: after an answer is shown, include a “Was this correct? If not, provide correction.” input. If a correction is submitted, Phoenix will call an internal API (that we implement in the orchestrator or memory service) to add the correction memory and flag it. Possibly, we then automatically re-run the query with the correction applied to show the improvement.
    
- _Task 3.3:_ **Container Orchestration & Config** – Write Dockerfiles for the custom services: the Python ingestion/retrieval service, the MCP memory server (if separate), and the Phoenix app. Use multi-stage builds to minimize image sizes (especially for Python with ML libs). In Docker Compose, define all services and their dependencies:
    
    - `neo4j` (with bolt on 7687, http on 7474),
        
    - `vectordb` (if Weaviate, expose 8080; if Chroma, maybe not needed externally),
        
    - `ollama` (if using as a separate container, or we instruct users to install it locally – better to containerize it for consistency),
        
    - `mcp-server`,
        
    - `rag-backend` (the Python service),
        
    - `phoenix-ui` (the Elixir app).  
        Also include possibly a `playwright` container or ensure the Python image has Playwright browsers installed (Playwright can run in a Docker image but needs the browsers; we might use the `mcr.microsoft.com/playwright/python` base image). Ensure networking is configured so that the Phoenix container can reach the Python service (e.g. via http://rag-backend:8000) and the Python can reach Neo4j etc., using service names. Configure volumes for persistent data: Neo4j data, maybe a volume for Chroma if using disk, and possibly a volume to save uploaded files (if we want to keep originals).
        
- _Task 3.4:_ **Testing & Performance Tuning** – With everything running in Compose, do end-to-end testing of typical flows: ingest a set of documents (of various types), crawl a sample site (perhaps a local wiki requiring login), ask questions that require combining info from multiple sources, correct an answer, etc. Monitor logs and resource usage. Tune chunk size and number of chunks `K` to pass into LLM (trade-off between completeness and prompt length). Evaluate latency of retrieval and whether any step is a bottleneck (embedding generation, vector search, graph query). We might introduce asynchronous processing in ingestion (Phoenix can show a “processing...” state while Python does the heavy work). Also, test with a larger data volume to ensure the system remains responsive (this might involve optimizing Neo4j queries with indexes, or batch writing in ingestion).
    
- _Task 3.5:_ **Documentation & Diagramming** – Finalize documentation of the system for developers: how to run, how to extend (for example, how to add a new file parser or integrate another LLM). Provide architecture diagrams (similar to the one above) in the README. Ensure all source citations or attributions (if any code was adapted from examples) are noted. Emphasize the modular design: e.g., a developer could swap out Neo4j for another graph DB by only changing the GraphDAO module, or add a new MCP tool for a different kind of memory. By the end, we want the project to be developer-friendly to modify or improve.
    
- _Milestone 3:_ The fully integrated system is running with a user-facing interface. A developer (or power user) can load their knowledge, query it, visualize how the answer was derived, correct the AI if needed, and see that correction persist. The system is containerized for easy deployment (whether on a local machine via Docker Compose, or scalable via Kubernetes on a server).
    

### Deployment Considerations

For development and small-scale use, **Docker Compose** will suffice to run everything on one host. In production or larger deployments, we can move to **Kubernetes** for better scalability: each component (vector DB, graph DB, ingestion worker, memory server, UI, LLM workers) can be a separate deployment, allowing horizontal scaling of stateless parts. For instance, if embedding or retrieval becomes a bottleneck, we can scale out multiple instances of the Python service behind a load balancer, all connecting to the same backing databases. Kubernetes also helps with deploying updates to individual services without downtime for the whole system. We will provide Helm charts or compose files for such scenarios as part of the implementation guide.

 

Security-wise, if the system is used with authenticated data sources, we will ensure secrets (like login credentials or API keys) are managed via environment variables and not logged. Phoenix can handle user authentication for the UI if needed (e.g. if multiple people use the system, though initially we target a single-developer usage).

## Rationale and Future Extensions

In summary, this contextual RAG system is built with **state-of-the-art techniques** – contextual embeddings, hybrid semantic+lexical search, and knowledge graph augmented reasoning – as demonstrated by Anthropic and others, to significantly improve retrieval fidelity[anthropic.com](https://www.anthropic.com/news/contextual-retrieval#:~:text=Our%20experiments%20showed%20that%3A). By combining a vector database for recall and a graph database for precision and reasoning, we get the best of both worlds in information retrieval[qdrant.tech](https://qdrant.tech/documentation/examples/graphrag-qdrant-neo4j/#:~:text=Advantages%20of%20Qdrant%20%2B%20Neo4j,GraphRAG)[cognee.ai](https://www.cognee.ai/blog/deep-dives/model-context-protocol-cognee-llm-memory-made-simple#:~:text=Cognee%20builds%20on%20these%20concepts,data%20structure%20alone%20might%20miss). The use of MCP for memory makes our solution future-proof and interoperable with emerging AI tools and standards[medium.com](https://medium.com/@nimritakoul01/the-model-context-protocol-mcp-a-complete-tutorial-a3abe8a7f4ef#:~:text=Model%20Context%20Protocol%20,problem%20of%20fragmented%20data%20access)[mem0.ai](https://mem0.ai/blog/how-to-make-your-clients-more-context-aware-with-openmemory-mcp#:~:text=Today%2C%20we%27re%20excited%20to%20present,compatible%20tool). All components chosen are open-source or standard protocols, aligning with the developer-centric and privacy-centric goal (you can run everything locally, including LLMs and embeddings, with no data leaving your environment).

 

The modular architecture allows easy extension: developers can plug in new data source connectors (e.g. a connector for Google Drive or Confluence pages) by adding to the ingestion service. New models can be integrated as they emerge (for example, replacing the embedding model with a future state-of-the-art one, or adding a domain-specific LLM for certain queries). The graph schema can evolve to capture more nuanced relationships or even user behavior patterns (for example, tracking which sources were most helpful for answers to continually improve retrieval ordering). The memory subsystem can be extended with more sophisticated forgetting policies (e.g. auto-expire certain memories after X days if not used) or versioning (keeping track of how knowledge changes over time).

 

By delivering information to the LLM in a context-aware, curated manner, we expect more accurate and explainable outputs from the assistant. In essence, this PRD outlines a **next-generation RAG system** that not only finds information but understands it in context – and continuously learns from interactions. It provides developers a powerful platform to build AI assistants that are deeply knowledgeable, **contextually aware**, and **adaptive** to corrections, all within a containerized, open framework.

 

**Sources:** The design draws on recent advancements in RAG such as Anthropic’s contextual retrieval method[anthropic.com](https://www.anthropic.com/news/contextual-retrieval#:~:text=In%20this%20post%2C%20we%20outline,better%20performance%20in%20downstream%20tasks)[anthropic.com](https://www.anthropic.com/news/contextual-retrieval#:~:text=concise%2C%20chunk,generate%20context%20for%20each%20chunk), hybrid search approaches combining dense vectors with BM25[anthropic.com](https://www.anthropic.com/news/contextual-retrieval#:~:text=1,prompt%20to%20generate%20the%20response), and GraphRAG frameworks that integrate knowledge graphs for complex reasoning[medium.com](https://medium.com/@zilliz_learn/graphrag-explained-enhancing-rag-with-knowledge-graphs-3312065f99e1#:~:text=To%20address%20such%20challenges%2C%20Microsoft,with%20the%20Milvus%20vector%20database)[qdrant.tech](https://qdrant.tech/documentation/examples/graphrag-qdrant-neo4j/#:~:text=Advantages%20of%20Qdrant%20%2B%20Neo4j,GraphRAG). The memory system is informed by the Model Context Protocol standard and existing implementations of persistent LLM memories[lobehub.com](https://lobehub.com/mcp/hridaya423-memory-mcp#:~:text=support%20for%20tags%2C%20timestamps%2C%20and,based%20on%20links%20and%20relationships)[mem0.ai](https://mem0.ai/blog/how-to-make-your-clients-more-context-aware-with-openmemory-mcp#:~:text=,delete_all_memories), ensuring our approach aligns with emerging best practices in AI tooling. All chosen technologies (Neo4j, Chroma/Weaviate, Playwright, etc.) are proven open-source solutions in their domains, providing a reliable foundation for implementation.

Citations

[

![](https://www.google.com/s2/favicons?domain=https://www.anthropic.com&sz=32)

Introducing Contextual Retrieval \ Anthropic

https://www.anthropic.com/news/contextual-retrieval

](https://www.anthropic.com/news/contextual-retrieval#:~:text=For%20an%20AI%20model%20to,vast%20array%20of%20past%20cases)[

![](https://www.google.com/s2/favicons?domain=https://www.anthropic.com&sz=32)

Introducing Contextual Retrieval \ Anthropic

https://www.anthropic.com/news/contextual-retrieval

](https://www.anthropic.com/news/contextual-retrieval#:~:text=Generation%20%28RAG%29,information%20from%20the%20knowledge%20base)[

![](https://www.google.com/s2/favicons?domain=https://www.anthropic.com&sz=32)

Introducing Contextual Retrieval \ Anthropic

https://www.anthropic.com/news/contextual-retrieval

](https://www.anthropic.com/news/contextual-retrieval#:~:text=In%20this%20post%2C%20we%20outline,better%20performance%20in%20downstream%20tasks)[

![](https://www.google.com/s2/favicons?domain=https://medium.com&sz=32)

Best Embedding Models.  OpenAI, Cohere, Google, E5, BGE | Medium

https://medium.com/@lars.chr.wiik/best-embedding-model-openai-cohere-google-e5-bge-931bfa1962dc

](https://medium.com/@lars.chr.wiik/best-embedding-model-openai-cohere-google-e5-bge-931bfa1962dc#:~:text=Microsoft%20has%20taken%20a%20unique,M3)[

![](https://www.google.com/s2/favicons?domain=https://elephas.app&sz=32)

13 Best Embedding Models in 2025: OpenAI vs Voyage AI vs Ollama | Complete Guide + Pricing & Performance

https://elephas.app/blog/best-embedding-models

](https://elephas.app/blog/best-embedding-models#:~:text=,with%20API%20keys%20of%20OpenAI)[

![](https://www.google.com/s2/favicons?domain=https://www.anthropic.com&sz=32)

Introducing Contextual Retrieval \ Anthropic

https://www.anthropic.com/news/contextual-retrieval

](https://www.anthropic.com/news/contextual-retrieval#:~:text=concise%2C%20chunk,generate%20context%20for%20each%20chunk)[

![](https://www.google.com/s2/favicons?domain=https://www.anthropic.com&sz=32)

Introducing Contextual Retrieval \ Anthropic

https://www.anthropic.com/news/contextual-retrieval

](https://www.anthropic.com/news/contextual-retrieval#:~:text=Copy)[

![](https://www.google.com/s2/favicons?domain=https://www.anthropic.com&sz=32)

Introducing Contextual Retrieval \ Anthropic

https://www.anthropic.com/news/contextual-retrieval

](https://www.anthropic.com/news/contextual-retrieval#:~:text=Contextual%20Retrieval%20solves%20this%20problem,%E2%80%9CContextual%20BM25%E2%80%9D)[

![](https://www.google.com/s2/favicons?domain=https://www.anthropic.com&sz=32)

Introducing Contextual Retrieval \ Anthropic

https://www.anthropic.com/news/contextual-retrieval

](https://www.anthropic.com/news/contextual-retrieval#:~:text=The%20resulting%20contextual%20text%2C%20usually,before%20creating%20the%20BM25%20index)[

![](https://www.google.com/s2/favicons?domain=https://www.anthropic.com&sz=32)

Introducing Contextual Retrieval \ Anthropic

https://www.anthropic.com/news/contextual-retrieval

](https://www.anthropic.com/news/contextual-retrieval#:~:text=Our%20experiments%20showed%20that%3A)[

![](https://www.google.com/s2/favicons?domain=https://qdrant.tech&sz=32)

GraphRAG with Qdrant and Neo4j - Qdrant

https://qdrant.tech/documentation/examples/graphrag-qdrant-neo4j/

](https://qdrant.tech/documentation/examples/graphrag-qdrant-neo4j/#:~:text=Advantages%20of%20Qdrant%20%2B%20Neo4j,GraphRAG)[

![](https://www.google.com/s2/favicons?domain=https://www.cognee.ai&sz=32)

Cognee - Model Context Protocol + Cognee: LLM Memory Made Simple

https://www.cognee.ai/blog/deep-dives/model-context-protocol-cognee-llm-memory-made-simple

](https://www.cognee.ai/blog/deep-dives/model-context-protocol-cognee-llm-memory-made-simple#:~:text=Cognee%20builds%20on%20these%20concepts,data%20structure%20alone%20might%20miss)[

![](https://www.google.com/s2/favicons?domain=https://medium.com&sz=32)

GraphRAG Explained: Enhancing RAG with Knowledge Graphs | by Zilliz | Medium

https://medium.com/@zilliz_learn/graphrag-explained-enhancing-rag-with-knowledge-graphs-3312065f99e1

](https://medium.com/@zilliz_learn/graphrag-explained-enhancing-rag-with-knowledge-graphs-3312065f99e1#:~:text=While%20this%20approach%20works%20well,connecting%20disparate%20pieces%20of%20information)[

![](https://www.google.com/s2/favicons?domain=https://medium.com&sz=32)

GraphRAG Explained: Enhancing RAG with Knowledge Graphs | by Zilliz | Medium

https://medium.com/@zilliz_learn/graphrag-explained-enhancing-rag-with-knowledge-graphs-3312065f99e1

](https://medium.com/@zilliz_learn/graphrag-explained-enhancing-rag-with-knowledge-graphs-3312065f99e1#:~:text=To%20address%20such%20challenges%2C%20Microsoft,with%20the%20Milvus%20vector%20database)[

![](https://www.google.com/s2/favicons?domain=https://www.anthropic.com&sz=32)

Introducing Contextual Retrieval \ Anthropic

https://www.anthropic.com/news/contextual-retrieval

](https://www.anthropic.com/news/contextual-retrieval#:~:text=While%20embedding%20models%20excel%20at,unique%20identifiers%20or%20technical%20terms)[

![](https://www.google.com/s2/favicons?domain=https://www.anthropic.com&sz=32)

Introducing Contextual Retrieval \ Anthropic

https://www.anthropic.com/news/contextual-retrieval

](https://www.anthropic.com/news/contextual-retrieval#:~:text=Here%E2%80%99s%20how%20BM25%20can%20succeed,to%20identify%20the%20relevant%20documentation)[

![](https://www.google.com/s2/favicons?domain=https://www.anthropic.com&sz=32)

Introducing Contextual Retrieval \ Anthropic

https://www.anthropic.com/news/contextual-retrieval

](https://www.anthropic.com/news/contextual-retrieval#:~:text=1,prompt%20to%20generate%20the%20response)[

![](https://www.google.com/s2/favicons?domain=https://python.langchain.com&sz=32)

Weaviate - ️ LangChain

https://python.langchain.com/docs/integrations/vectorstores/weaviate/

](https://python.langchain.com/docs/integrations/vectorstores/weaviate/#:~:text=A%20hybrid%20search%20combines%20a,allows%20you%20to%20pass)[

![](https://www.google.com/s2/favicons?domain=https://www.anthropic.com&sz=32)

Introducing Contextual Retrieval \ Anthropic

https://www.anthropic.com/news/contextual-retrieval

](https://www.anthropic.com/news/contextual-retrieval#:~:text=failed%20retrievals%20by%2049,better%20performance%20in%20downstream%20tasks)[

![](https://www.google.com/s2/favicons?domain=https://medium.com&sz=32)

GraphRAG Explained: Enhancing RAG with Knowledge Graphs | by Zilliz | Medium

https://medium.com/@zilliz_learn/graphrag-explained-enhancing-rag-with-knowledge-graphs-3312065f99e1

](https://medium.com/@zilliz_learn/graphrag-explained-enhancing-rag-with-knowledge-graphs-3312065f99e1#:~:text=1,construct%20an%20initial%20knowledge%20graph)[

![](https://www.google.com/s2/favicons?domain=https://medium.com&sz=32)

The Model Context Protocol (MCP) — A Complete Tutorial | by Dr. Nimrita Koul | Medium

https://medium.com/@nimritakoul01/the-model-context-protocol-mcp-a-complete-tutorial-a3abe8a7f4ef

](https://medium.com/@nimritakoul01/the-model-context-protocol-mcp-a-complete-tutorial-a3abe8a7f4ef#:~:text=,Build%20composable%20integrations%20and%20workflows)[

![](https://www.google.com/s2/favicons?domain=https://medium.com&sz=32)

The Model Context Protocol (MCP) — A Complete Tutorial | by Dr. Nimrita Koul | Medium

https://medium.com/@nimritakoul01/the-model-context-protocol-mcp-a-complete-tutorial-a3abe8a7f4ef

](https://medium.com/@nimritakoul01/the-model-context-protocol-mcp-a-complete-tutorial-a3abe8a7f4ef#:~:text=Model%20Context%20Protocol%20,problem%20of%20fragmented%20data%20access)[

![](https://www.google.com/s2/favicons?domain=https://lobehub.com&sz=32)

Memory Server MCP | MCP Servers · LobeHub

https://lobehub.com/mcp/hridaya423-memory-mcp

](https://lobehub.com/mcp/hridaya423-memory-mcp#:~:text=support%20for%20tags%2C%20timestamps%2C%20and,based%20on%20links%20and%20relationships)[

![](https://www.google.com/s2/favicons?domain=https://lobehub.com&sz=32)

Memory Server MCP | MCP Servers · LobeHub

https://lobehub.com/mcp/hridaya423-memory-mcp

](https://lobehub.com/mcp/hridaya423-memory-mcp#:~:text=,with%20a%20specified%20relationship%20type)[

![](https://www.google.com/s2/favicons?domain=https://lobehub.com&sz=32)

Claude Code Memory Server | MCP Servers · LobeHub

https://lobehub.com/mcp/viralvoodoo-claude-code-memory

](https://lobehub.com/mcp/viralvoodoo-claude-code-memory#:~:text=Advanced%20Intelligence)[

![](https://www.google.com/s2/favicons?domain=https://mem0.ai&sz=32)

AI Memory OpenMemory MCP: Context-Aware Clients Guide | Mem0

https://mem0.ai/blog/how-to-make-your-clients-more-context-aware-with-openmemory-mcp

](https://mem0.ai/blog/how-to-make-your-clients-more-context-aware-with-openmemory-mcp#:~:text=In%20the%20rapidly%20evolving%20landscape,they%20forget%20everything%20between%20sessions)[

![](https://www.google.com/s2/favicons?domain=https://mem0.ai&sz=32)

AI Memory OpenMemory MCP: Context-Aware Clients Guide | Mem0

https://mem0.ai/blog/how-to-make-your-clients-more-context-aware-with-openmemory-mcp

](https://mem0.ai/blog/how-to-make-your-clients-more-context-aware-with-openmemory-mcp#:~:text=,delete_all_memories)[

![](https://www.google.com/s2/favicons?domain=https://cloud.google.com&sz=32)

GraphRAG infrastructure for generative AI using Vertex AI and Spanner Graph  |  Cloud Architecture Center  |  Google Cloud

https://cloud.google.com/architecture/gen-ai-graphrag-spanner

](https://cloud.google.com/architecture/gen-ai-graphrag-spanner#:~:text=Architecture)[

![](https://www.google.com/s2/favicons?domain=https://weaviate.io&sz=32)

A Web Developers Guide to Hybrid Search - Weaviate

https://weaviate.io/blog/hybrid-search-for-web-developers

](https://weaviate.io/blog/hybrid-search-for-web-developers#:~:text=Hybrid%20search%20in%20Weaviate%20combines,term%20matching%20and%20semantic%20context)[

![](https://www.google.com/s2/favicons?domain=https://www.anthropic.com&sz=32)

Introducing Contextual Retrieval \ Anthropic

https://www.anthropic.com/news/contextual-retrieval

](https://www.anthropic.com/news/contextual-retrieval#:~:text=Further%20boosting%20performance%20with%20Reranking)[

![](https://www.google.com/s2/favicons?domain=https://www.anthropic.com&sz=32)

Introducing Contextual Retrieval \ Anthropic

https://www.anthropic.com/news/contextual-retrieval

](https://www.anthropic.com/news/contextual-retrieval#:~:text=1,to%20generate%20the%20final%20result)[

![](https://www.google.com/s2/favicons?domain=https://mem0.ai&sz=32)

AI Memory OpenMemory MCP: Context-Aware Clients Guide | Mem0

https://mem0.ai/blog/how-to-make-your-clients-more-context-aware-with-openmemory-mcp

](https://mem0.ai/blog/how-to-make-your-clients-more-context-aware-with-openmemory-mcp#:~:text=,delete_all_memories)[

![](https://www.google.com/s2/favicons?domain=https://mem0.ai&sz=32)

AI Memory OpenMemory MCP: Context-Aware Clients Guide | Mem0

https://mem0.ai/blog/how-to-make-your-clients-more-context-aware-with-openmemory-mcp

](https://mem0.ai/blog/how-to-make-your-clients-more-context-aware-with-openmemory-mcp#:~:text=,vector%20store%20under%20the%20hood)[

![](https://www.google.com/s2/favicons?domain=https://lobehub.com&sz=32)

Claude Code Memory Server | MCP Servers · LobeHub

https://lobehub.com/mcp/viralvoodoo-claude-code-memory

](https://lobehub.com/mcp/viralvoodoo-claude-code-memory#:~:text=This%20MCP%20server%20creates%20a,development%20concepts%2C%20solutions%2C%20and%20workflows)[

![](https://www.google.com/s2/favicons?domain=https://lobehub.com&sz=32)

Memory Server MCP | MCP Servers · LobeHub

https://lobehub.com/mcp/hridaya423-memory-mcp

](https://lobehub.com/mcp/hridaya423-memory-mcp#:~:text=stored%20memories%20,based%20on%20links%20and%20relationships)[

![](https://www.google.com/s2/favicons?domain=https://medium.com&sz=32)

The Model Context Protocol (MCP) — A Complete Tutorial | by Dr. Nimrita Koul | Medium

https://medium.com/@nimritakoul01/the-model-context-protocol-mcp-a-complete-tutorial-a3abe8a7f4ef

](https://medium.com/@nimritakoul01/the-model-context-protocol-mcp-a-complete-tutorial-a3abe8a7f4ef#:~:text=The%20protocol%20uses%20JSON,messages%20to%20establish%20communication%20between)[

![](https://www.google.com/s2/favicons?domain=https://elephas.app&sz=32)

13 Best Embedding Models in 2025: OpenAI vs Voyage AI vs Ollama | Complete Guide + Pricing & Performance

https://elephas.app/blog/best-embedding-models

](https://elephas.app/blog/best-embedding-models#:~:text=Ollama)[

![](https://www.google.com/s2/favicons?domain=https://lobehub.com&sz=32)

Claude Code Memory Server | MCP Servers · LobeHub

https://lobehub.com/mcp/viralvoodoo-claude-code-memory

](https://lobehub.com/mcp/viralvoodoo-claude-code-memory#:~:text=%2A%20Relationship%20Mapping%20,specific%20memory%20retrieval)[

![](https://www.google.com/s2/favicons?domain=https://www.anthropic.com&sz=32)

Introducing Contextual Retrieval \ Anthropic

https://www.anthropic.com/news/contextual-retrieval

](https://www.anthropic.com/news/contextual-retrieval#:~:text=3,prompt%20to%20generate%20the%20response)[

![](https://www.google.com/s2/favicons?domain=https://medium.com&sz=32)

The Model Context Protocol (MCP) — A Complete Tutorial | by Dr. Nimrita Koul | Medium

https://medium.com/@nimritakoul01/the-model-context-protocol-mcp-a-complete-tutorial-a3abe8a7f4ef

](https://medium.com/@nimritakoul01/the-model-context-protocol-mcp-a-complete-tutorial-a3abe8a7f4ef#:~:text=It%20is%20developed%20by%20Mahesh,Python%20SDK%20and%20TypeScript%20SDK)[

![](https://www.google.com/s2/favicons?domain=https://cloud.google.com&sz=32)

GraphRAG infrastructure for generative AI using Vertex AI and Spanner Graph  |  Cloud Architecture Center  |  Google Cloud

https://cloud.google.com/architecture/gen-ai-graphrag-spanner

](https://cloud.google.com/architecture/gen-ai-graphrag-spanner#:~:text=3,or%20Document%20AI%27s%20Layout%20Parser)[

![](https://www.google.com/s2/favicons?domain=https://cloud.google.com&sz=32)

GraphRAG infrastructure for generative AI using Vertex AI and Spanner Graph  |  Cloud Architecture Center  |  Google Cloud

https://cloud.google.com/architecture/gen-ai-graphrag-spanner

](https://cloud.google.com/architecture/gen-ai-graphrag-spanner#:~:text=7,graph%20nodes%20in%20Spanner%20Graph)[

![](https://www.google.com/s2/favicons?domain=https://lobehub.com&sz=32)

Memory Server MCP | MCP Servers · LobeHub

https://lobehub.com/mcp/hridaya423-memory-mcp

](https://lobehub.com/mcp/hridaya423-memory-mcp#:~:text=memories%2C%20and%20find%20related%20content,based%20on%20links%20and%20relationships)[

![](https://www.google.com/s2/favicons?domain=https://mem0.ai&sz=32)

AI Memory OpenMemory MCP: Context-Aware Clients Guide | Mem0

https://mem0.ai/blog/how-to-make-your-clients-more-context-aware-with-openmemory-mcp

](https://mem0.ai/blog/how-to-make-your-clients-more-context-aware-with-openmemory-mcp#:~:text=Today%2C%20we%27re%20excited%20to%20present,compatible%20tool)

All Sources

[

![](https://www.google.com/s2/favicons?domain=https://www.anthropic.com&sz=32)

anthropic

](https://www.anthropic.com/news/contextual-retrieval#:~:text=For%20an%20AI%20model%20to,vast%20array%20of%20past%20cases)[

![](https://www.google.com/s2/favicons?domain=https://medium.com&sz=32)

medium

](https://medium.com/@lars.chr.wiik/best-embedding-model-openai-cohere-google-e5-bge-931bfa1962dc#:~:text=Microsoft%20has%20taken%20a%20unique,M3)[

![](https://www.google.com/s2/favicons?domain=https://elephas.app&sz=32)

elephas

](https://elephas.app/blog/best-embedding-models#:~:text=,with%20API%20keys%20of%20OpenAI)[

![](https://www.google.com/s2/favicons?domain=https://qdrant.tech&sz=32)

qdrant

](https://qdrant.tech/documentation/examples/graphrag-qdrant-neo4j/#:~:text=Advantages%20of%20Qdrant%20%2B%20Neo4j,GraphRAG)[

![](https://www.google.com/s2/favicons?domain=https://www.cognee.ai&sz=32)

cognee

](https://www.cognee.ai/blog/deep-dives/model-context-protocol-cognee-llm-memory-made-simple#:~:text=Cognee%20builds%20on%20these%20concepts,data%20structure%20alone%20might%20miss)[

![](https://www.google.com/s2/favicons?domain=https://python.langchain.com&sz=32)

python.langchain

](https://python.langchain.com/docs/integrations/vectorstores/weaviate/#:~:text=A%20hybrid%20search%20combines%20a,allows%20you%20to%20pass)[

![](https://www.google.com/s2/favicons?domain=https://lobehub.com&sz=32)

lobehub

](https://lobehub.com/mcp/hridaya423-memory-mcp#:~:text=support%20for%20tags%2C%20timestamps%2C%20and,based%20on%20links%20and%20relationships)[

![](https://www.google.com/s2/favicons?domain=https://mem0.ai&sz=32)

mem0

](https://mem0.ai/blog/how-to-make-your-clients-more-context-aware-with-openmemory-mcp#:~:text=In%20the%20rapidly%20evolving%20landscape,they%20forget%20everything%20between%20sessions)[

![](https://www.google.com/s2/favicons?domain=https://cloud.google.com&sz=32)

cloud.google

](https://cloud.google.com/architecture/gen-ai-graphrag-spanner#:~:text=Architecture)[

![](https://www.google.com/s2/favicons?domain=https://weaviate.io&sz=32)



](https://weaviate.io/blog/hybrid-search-for-web-developers#:~:text=Hybrid%20search%20in%20Weaviate%20combines,term%20matching%20and%20semantic%20context)