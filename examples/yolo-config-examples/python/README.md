# Python Data Science Example

A Python project with a custom Dockerfile that includes data science libraries.

## Structure

```
.yolo/
├── strategy       # Force Python strategy
├── Dockerfile     # Custom image with pandas, numpy, etc.
├── env            # Environment variables
└── ports          # Port mappings
```

## Files

### `strategy`
```
python
```

### `Dockerfile`
```dockerfile
FROM python:3.11-slim

RUN apt-get update && apt-get install -y \
    build-essential \
    libpq-dev

RUN pip install --no-cache-dir \
    pandas \
    numpy \
    scikit-learn \
    jupyter \
    pytest

WORKDIR /workspace
CMD ["bash"]
```

### `env`
```bash
PYTHONUNBUFFERED=1
DEBUG=True
DATABASE_URL=postgresql://localhost/myapp
```

### `ports`
```
5000:5000    # Flask/FastAPI
8888:8888    # Jupyter
```

## Use Case

You're working on a data science project and need Python libraries that aren't in the default Python strategy Dockerfile. You create a custom Dockerfile with pandas, numpy, scikit-learn, and Jupyter.

## Copy This Example

```bash
mkdir -p .yolo
cp examples/yolo-config-examples/python/* .yolo/
nano .yolo/Dockerfile  # Add your dependencies
```

## Customization

Add more Python packages to the Dockerfile:

```dockerfile
RUN pip install --no-cache-dir \
    tensorflow \
    torch \
    matplotlib \
    seaborn
```

Or use a requirements.txt:

```dockerfile
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
```

## Running Jupyter

Start the container and run Jupyter:

```bash
claude-yolo --yolo --trust-yolo

# In the container:
jupyter notebook --ip=0.0.0.0 --port=8888 --no-browser --allow-root

# Access at: http://localhost:8888
```
