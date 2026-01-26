# CDH5 Docker (Apple Silicon Compatible)

This repository documents how to run the Cloudera CDH5 training environment using Docker on Apple Silicon (M1/M2/M3).

The Docker image is published via GitHub Container Registry (GHCR).

## Prerequisites
- Docker Desktop (macOS)
- Recommended: Enable Rosetta for x86_64 emulation in Docker Desktop settings

## Pull the image
```bash
docker pull ghcr.io/stevenqcly/cloudera-cdh5:cdh5

