# WehniRoute 0.6.0

WehniRoute 0.6.0 makes every mainstream local AI inference engine a first-class, auto-detectable provider, and makes the router fail over at *model* granularity within a provider before moving to the next provider.

## Local engines, everywhere
- 18 new detectable local inference engines: Jan, GPT4All, KoboldCpp, Text Generation WebUI, TabbyAPI, llama.cpp server, llamafile, LocalAI, Hugging Face TGI, MLX-LM, vLLM, llama-cpp-python, SGLang, mistral.rs, Xinference, Docker Model Runner, AMD Lemonade, LiteLLM Proxy.
- Shared ports (8080, 8000, 5000, 1234) are disambiguated by engine-specific probes instead of guessed.
- llama.cpp servers are detected on both the classic 8080 port and the new 9931 default; TabbyAPI asks for its API key (its server requires auth by default).

## Smarter failover
- New "Failover scope" routing option: Global (previous behavior) or Provider first — exhaust a provider's own models by score before falling over to the next provider.
- Per-model health tracking: one misbehaving model cools down alone; its provider's other models stay in rotation.
