# Oracle APEX Full Installer for Ubuntu 22.04

Beginner friendly one-click installer for:

- Oracle Database Free
- Oracle APEX 26.1
- Oracle REST Data Services (ORDS)
- Docker
- Nginx
- Java 17

Designed for:
- Ubuntu 22.04
- Contabo VPS
- Local Ubuntu servers
- Oracle APEX learners and developers

---

# Features

- Fully automated installation
- Minimal user interaction
- Docker-based Oracle Database setup
- Real Oracle APEX installation
- ORDS configuration
- Nginx reverse proxy
- Firewall configuration
- Beginner friendly

---

# Requirements

Recommended VPS or Server Specs:

| Resource | Minimum | Recommended |
|---|---|---|
| CPU | 4 vCPU | 8 vCPU |
| RAM | 8 GB | 16 GB |
| Storage | 100 GB SSD | 200 GB SSD |
| OS | Ubuntu 22.04 | Ubuntu 22.04 |

---

# Installation

## Step 1 — Connect to Server

```bash
ssh root@YOUR_SERVER_IP
```

---

## Step 2 — Download Installer

```bash
wget https://raw.githubusercontent.com/pvsairam/Oracle-APEX/main/apex.sh
```

---

## Step 3 — Make Script Executable

```bash
chmod +x apex.sh
```

---

## Step 4 — Run Installer

```bash
sudo ./apex.sh
```

---

# Direct One-Line Installation

```bash
wget -O - https://raw.githubusercontent.com/pvsairam/Oracle-APEX/main/apex.sh | sudo bash
```

---

# Access Oracle APEX

After installation completes:

```text
http://YOUR_SERVER_IP/ords
```

or

```text
http://YOUR_SERVER_IP:8181/ords
```

---

# Default Login

Workspace:

```text
INTERNAL
```

Username:

```text
ADMIN
```

Password:

```text
Displayed after installation
```

---

# Installed Components

| Component | Purpose |
|---|---|
| Oracle Database Free | Database |
| Oracle APEX 26.1 | Low-code platform |
| ORDS | Web listener |
| Docker | Container runtime |
| Nginx | Reverse proxy |
| Java 17 | Required for ORDS |

---

# Useful Commands

## Check Running Containers

```bash
docker ps
```

## View ORDS Logs

```bash
docker logs -f ords
```

## View Database Logs

```bash
docker logs -f oracle-free
```

## Restart Services

```bash
docker compose restart
```

## Stop Services

```bash
docker compose down
```

## Start Services

```bash
docker compose up -d
```

---

# Security Recommendations

Please change default passwords after installation.

Do not expose database ports publicly unless required.

Recommended:
- Enable SSL
- Use strong passwords
- Restrict port access
- Configure backups

---

# Notes

This project uses Docker because Oracle Database is not officially supported for native installation on Ubuntu.

The installer runs real Oracle Database and real Oracle APEX internally using containers.

---

# Official Oracle Documentation

Oracle APEX:

https://www.oracle.com/apex/

Installation Guide:

https://docs.oracle.com/en/database/oracle/apex/26.1/htmig/index.html

Full Documentation:

https://docs.oracle.com/en/database/oracle/apex/26.1/index.html

---

# Disclaimer

This project is intended for:
- Learning
- Development
- Testing
- Sandbox environments

Please review Oracle licensing and production requirements before enterprise deployment.

---

# Author

Sairam
