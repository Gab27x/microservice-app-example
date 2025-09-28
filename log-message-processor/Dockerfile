# Usar Python 3.7 (versión común para este tipo de procesadores)
FROM python:3.7-slim

WORKDIR /app

RUN apt-get update && apt-get install -y \
    build-essential \
    gcc \
    python3-dev \
    && rm -rf /var/lib/apt/lists/*


COPY requirements.txt .

#Install code dependecies.
RUN pip install  -r requirements.txt

COPY . .
ENV PYTHONUNBUFFERED=1
CMD [ "python","-u", "main.py" ]