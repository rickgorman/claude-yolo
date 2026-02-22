FROM python:3.11-slim

# Install system dependencies for data science
RUN apt-get update && apt-get install -y \
    build-essential \
    curl \
    git \
    libpq-dev \
    && rm -rf /var/lib/apt/lists/*

# Install Python packages
RUN pip install --no-cache-dir \
    pandas \
    numpy \
    scikit-learn \
    jupyter \
    pytest \
    black \
    flake8

WORKDIR /workspace

# Default command
CMD ["bash"]
