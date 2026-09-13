# LLM and AI Crawler Usage Policy

**Last updated:** 2026-09-03

This document defines the rules for using content from `https://tabuamare.api.br` and the **Tábua de Maré API** by language models (LLMs), artificial intelligence crawlers, and automated scraping systems.

## 1. Allowed uses

- Indexing by traditional search engines that respect `robots.txt`.
- Indexing public HTML pages by `OAI-SearchBot` and `Claude-SearchBot` for search results.
- Retrieving public HTML pages through `Claude-User` in response to a user request.
- Brief summaries or quotations of public HTML pages with a link back to the source in search results.
- Consuming data exclusively through the official API endpoints (`/api/v2/*`), respecting rate limits, authentication, and terms of use.
- Reading this file (`/llm.md`) by crawlers that want to learn the usage policy.
- Reading `/llms.txt`, the official API documentation, and the OpenAPI specification on demand to answer a user request or build an integration that respects these rules.

## 2. Prohibited uses without prior written authorization

- Training, fine-tuning, aligning, or adapting AI models using any content from this website or API.
- Building databases, embeddings, semantic vectors, or synthesized datasets from tide, harbor, coordinate, or documentation data.
- Mass reproduction, mirroring, public caching, or republication of the data.
- Bulk ingestion of site or API content into RAG (retrieval-augmented generation) systems, chatbots, or automated assistants without express licensing.
- Ignoring, bypassing, or circumventing `robots.txt`, rate limits, authentication, or technical protections of the site.

## 3. API vs. scraping

Tide data must be consumed **exclusively through the documented endpoints**. Except for the search indexing and user-requested retrieval allowed above, scraping HTML pages, documentation, playground, dashboard, or other assets is expressly prohibited.

## 4. Contact and licensing

For commercial licensing, large-scale access, integration into AI products, or any use not covered by this policy, please contact us through the official channels at `https://tabuamare.api.br`.

## 5. Enforcement

Non-compliance with this policy may result in:

- Blocking of IPs, IP ranges, and user agents.
- Revocation of API keys and user accounts.
- Notification to hosting and CDN providers.
- Legal measures under Brazilian law (Law No. 9,610/98, LGPD, Marco Civil da Internet) and international copyright treaties.
