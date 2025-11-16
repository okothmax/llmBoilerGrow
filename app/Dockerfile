FROM python:3.11-slim

ENV PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /workspace

# Install system dependencies and Node.js
RUN apt-get update \
    && apt-get install -y --no-install-recommends curl gnupg \
    && curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && apt-get purge -y curl gnupg \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Python dependencies
COPY app/requirements.txt ./requirements.txt
RUN pip install -r requirements.txt

# Node dependencies
COPY agent_service/package.json ./agent_service/package.json
RUN npm install --prefix agent_service --omit=dev

# Application source
COPY . ./

# Startup script
RUN chmod +x ./start.sh

EXPOSE 80 3000

CMD ["./start.sh"]