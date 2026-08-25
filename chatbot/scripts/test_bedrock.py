import os
from dotenv import load_dotenv
from openai import OpenAI

load_dotenv()

OPENAI_API_KEY = os.getenv("OPENAI_API_KEY")
OPENAI_BASE_URL = os.getenv("OPENAI_BASE_URL")
MODEL_ID = os.getenv("MODEL_ID")
REGION = "us-east-1"

client = OpenAI(api_key=OPENAI_API_KEY, base_url=OPENAI_BASE_URL)
completion = client.chat.completions.create(
    model=MODEL_ID,
    messages=[{"role": "user", "content": "Who was the first person to land on the moon?"}],
)

print(completion.choices[0].message.content)