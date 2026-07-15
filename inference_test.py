"""
Load and chat with your fine-tuned jothidam/matrimony LLM.

Run this AFTER fine-tuning (finetune_llm.ipynb) and downloading the
'jothidam_llm_merged' folder from Colab to this machine (or a GPU server).

Usage:
    python inference_test.py
"""

from transformers import AutoModelForCausalLM, AutoTokenizer
import torch

MODEL_PATH = "jothidam_llm_merged"  # path to your fine-tuned model folder

SYSTEM_PROMPT = (
    "You are a jothidam (astrology) and matrimony matching assistant. "
    "Only answer questions about horoscope matching, Porutham, dosham, Nakshatra, Rasi, "
    "and matrimony/profile matching. If asked anything outside this field, politely say "
    "it is outside your area and redirect to jothidam/matrimony topics."
)


def load_model():
    tokenizer = AutoTokenizer.from_pretrained(MODEL_PATH)
    model = AutoModelForCausalLM.from_pretrained(
        MODEL_PATH,
        torch_dtype=torch.float16,
        device_map="auto",
    )
    return model, tokenizer


def ask(model, tokenizer, question, max_new_tokens=256):
    prompt = (
        f"<|im_start|>system\n{SYSTEM_PROMPT}<|im_end|>\n"
        f"<|im_start|>user\n{question}<|im_end|>\n"
        f"<|im_start|>assistant\n"
    )
    inputs = tokenizer([prompt], return_tensors="pt").to(model.device)
    outputs = model.generate(
        **inputs,
        max_new_tokens=max_new_tokens,
        do_sample=True,
        temperature=0.7,
        top_p=0.9,
    )
    text = tokenizer.decode(outputs[0], skip_special_tokens=True)
    # Return only the assistant's reply portion
    return text.split("assistant")[-1].strip()


if __name__ == "__main__":
    model, tokenizer = load_model()
    print("Jothidam/Matrimony LLM loaded. Type 'exit' to quit.\n")

    while True:
        q = input("You: ")
        if q.strip().lower() in ("exit", "quit"):
            break
        answer = ask(model, tokenizer, q)
        print(f"Assistant: {answer}\n")
