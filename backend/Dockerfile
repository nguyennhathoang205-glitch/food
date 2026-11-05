FROM python:3.11-slim

ENV PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PORT=7860

RUN apt-get update && apt-get install -y --no-install-recommends \
    libgl1 libglib2.0-0 \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# torch ban CPU (nhe hon nhieu so voi ban CUDA)
RUN pip install torch==2.5.1 torchvision==0.20.1 --index-url https://download.pytorch.org/whl/cpu

COPY requirements-deploy.txt .
RUN pip install -r requirements-deploy.txt

COPY . .

EXPOSE 7860
CMD ["gunicorn", "-b", "0.0.0.0:7860", "-w", "1", "--threads", "4", "--timeout", "180", "app:app"]
