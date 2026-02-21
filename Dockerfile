FROM python:3.12-slim

# Install ODBC Driver 18 for SQL Server
RUN apt-get update && \
    apt-get install -y --no-install-recommends curl gnupg2 apt-transport-https && \
    curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor -o /usr/share/keyrings/microsoft-prod.gpg && \
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/microsoft-prod.gpg] https://packages.microsoft.com/debian/12/prod bookworm main" > /etc/apt/sources.list.d/mssql-release.list && \
    apt-get update && \
    ACCEPT_EULA=Y apt-get install -y --no-install-recommends msodbcsql18 unixodbc-dev && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy source and install
COPY . .
RUN pip install --no-cache-dir .

# Run as non-root user
RUN useradd -r -s /usr/sbin/nologin sentinel
USER sentinel

EXPOSE 8000

CMD ["python", "-m", "uvicorn", "sentinel.api.main:app", "--host", "0.0.0.0", "--port", "8000"]
