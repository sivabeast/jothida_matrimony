# Jothidam / Matrimony Custom LLM — Guide

Your own AI, fine-tuned only on your field (jothidam + matrimony matching). It will
refuse or redirect questions outside this domain.

## Files added for this

- `training_data.jsonl` — 10 sample Q&A examples (jothidam/matrimony + 2 off-topic refusal examples). **Replace/expand this with your real data.**
- `finetune_llm.ipynb` — Colab notebook that fine-tunes Qwen2.5-7B-Instruct on your data using QLoRA (free T4 GPU).
- `inference_test.py` — Script to chat with your fine-tuned model after training.
- `requirements.txt` — Python packages needed (note: this is separate from your Flutter app's `pubspec.yaml`; this is for the Python fine-tuning pipeline, not the app itself).

## Step-by-step

### 1. Build your real training data
Expand `training_data.jsonl` to 200–1000+ examples covering:
- Horoscope matching rules (Porutham, Dosham, Nakshatra, Rasi)
- Common customer questions from your platform
- Matrimony profile / matching process questions
- **20–30 examples where the question is off-topic (weather, movies, coding, etc.) and the answer politely declines** — this teaches the model to stay in your field.

Format — one JSON object per line:
```json
{"instruction": "question here", "input": "", "output": "answer here"}
```

Tips to build this faster:
- Export real customer support chat logs / FAQs, convert to this format.
- Use ChatGPT/Claude itself to help draft more Q&A pairs from your existing jothidam content, then review for accuracy — a jothidam expert should verify the astrology answers before training.

### 2. Fine-tune
1. Open `finetune_llm.ipynb` in Google Colab (colab.research.google.com > Upload notebook).
2. Runtime > Change runtime type > **T4 GPU** (free tier).
3. Upload your `training_data.jsonl` to the Colab session (left sidebar > Files > upload).
4. Run all cells top to bottom. Training ~15–40 minutes depending on data size.
5. Download the resulting `jothidam_llm_merged` folder (or push it to your own private Hugging Face repo — see commented-out line in the notebook).

### 3. Test locally
```bash
pip install -r requirements.txt
python inference_test.py
```
Ask it domain questions and off-topic questions to confirm it behaves correctly.

### 4. Deploy and connect to your Flutter app
Options, easiest first:
- **Hugging Face Inference Endpoints** — upload your merged model, get an API URL, call it from your Flutter app via `http` package like any other REST API.
- **Your own GPU server** — run `inference_test.py`-style code behind a FastAPI/Flask endpoint, call that endpoint from Flutter.
- **Ollama** — convert the merged model to GGUF format and run it locally/cheaply on CPU for smaller-scale usage, expose via a small API for the app to call.

### 5. Iterate
As you get real user questions, add the good Q&A pairs (and any off-topic ones the model handled wrong) back into `training_data.jsonl` and re-run fine-tuning periodically. This is how the model keeps improving for your field specifically.

## Cost expectation
- Colab free T4 GPU: ₹0 for fine-tuning a 7B model with a few hundred examples.
- If you outgrow free Colab: Colab Pro (~$10/month) or a cloud GPU (RunPod/Lambda, ~$0.5–1/hour) for larger runs.
- Hugging Face Inference Endpoint for hosting: pay-as-you-go, roughly $0.5–2/hour depending on GPU size (or free if self-hosted).

## Why Qwen2.5-7B-Instruct as the base
- Ungated (no approval wait, unlike Llama 3).
- Strong multilingual support (handles Tamil + English mixed content well, useful for jothidam terminology).
- Fits in free Colab T4 GPU with 4-bit quantization.
- Alternatives: Mistral-7B-Instruct, Llama-3-8B-Instruct (needs Hugging Face gated access approval), Gemma-2-9B.
