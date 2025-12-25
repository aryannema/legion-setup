# 📄 `README.md` — **Python Project**

# Python Project (Windows · conda + uv)

This project was generated using `new-python-project.bat`.

The Python workflow is intentionally simple and explicit:

- **conda** manages the Python environment
- **uv** installs Python packages from `requirements.txt`
- Project metadata is stored in `project_config.yaml`
- No TOML files are used

---

## Prerequisites (install once)

### 1. Conda

Install **Miniconda** or **Anaconda**.

Verify in CMD:

```
conda --version
```

If this fails, use **Anaconda Prompt / Miniconda Prompt**, or run once:

```
conda init cmd.exe

```

Then reopen CMD.

---

### 2. uv

Install `uv` and ensure it is on PATH:

```bat
uv --version
```

---

## Project Structure

```
project/
│
├─ src/
│  └─ main.py
│
├─ requirements.txt
├─ project_config.yaml
│
├─ scripts/
│  ├─ dev.cmd
│  ├─ run.cmd
│  └─ validate_tf.cmd   (only if --tf was used)
│
└─ .vscode/
   └─ settings.json
```

---

## Environment Setup & Dependency Installation

The generator provides `scripts\dev.cmd` which:

- creates a **conda environment (prefix-based)**
- activates it
- installs dependencies using **uv**

From the project root:

```bat
scripts\dev.cmd
```

If activation fails, run the command from **Anaconda Prompt**.

---

## Running the Program

After setup completes:

```bat
scripts\run.cmd
```

This runs:

```bat
python src\main.py
```

---

## VS Code Interpreter Selection (Important)

This project auto-generates:

```
.vscode/settings.json
```

Pointing VS Code to:

```
D:\dev\envs\conda\<project_name>\python.exe
```

If VS Code still shows import errors:

1. Press `Ctrl+Shift+P`
2. Run **Python: Select Interpreter**
3. Choose the interpreter under the project’s conda env
4. Restart VS Code once

---

## TensorFlow Projects (`--tf` only)

If this project was created with `--tf`:

### Install

TensorFlow is already listed in `requirements.txt`:

```bat
scripts\dev.cmd
```

### Validate (Recommended)

```bat
scripts\validate_tf.cmd
```

This checks:

- TensorFlow import
- GPU visibility
- CUDA/XLA warm-up
- Memory growth settings (prevents VRAM hogging)

⚠️ First GPU run may be slow — this is normal.

---

## Troubleshooting

### Conda activates in Prompt but not CMD

Run once:

```bat
conda init cmd.exe
```

### VS Code shows missing imports but code runs

Interpreter mismatch — reselect interpreter and restart VS Code.

---

# 📄 `README.md` — **Node.js Project**

# Node.js Project (Minimal · Windows)

This project was generated using `new-node-project.bat`.

The goal is a **clean, minimal Node scaffold**:

- No frameworks (no Vite, Next, etc.)
- Plain `node` execution
- Metadata recorded in `project_config.yaml`
- AI / TF flags are documentation-only

---

## Prerequisites (install once)

### 1. Node.js

Install Node.js (LTS recommended).

Verify:

```bat
node --version
npm --version
```

---

## Project Structure

```
project/
│
├─ src/
│  └─ index.js
│
├─ package.json
├─ project_config.yaml
│
├─ scripts/
│  ├─ dev.cmd
│  └─ run.cmd
│
└─ .gitignore
```

---

## Install Dependencies

This scaffold starts with **no dependencies**.

If you add dependencies later:

```bat
pnpm install
```

(or `npm install` / `yarn install` if you prefer)

---

## Running the Program

### Development Mode

```bat
scripts\dev.cmd
```

Uses:

```bat
node --watch src/index.js
```

### Run Once

```bat
scripts\run.cmd
```

Uses:

```bat
node src/index.js
```

---

## VS Code Setup

No interpreter selection required.

Recommended extensions:

- JavaScript and TypeScript Language Features (built-in)
- ESLint (optional)

---

## AI / TensorFlow Notes (`--ai`, `--tf`)

If generated with `--ai` or `--tf`, notes are added to `project_config.yaml`.

Important guidance:

- Node is **not recommended** for TensorFlow-heavy workflows on Windows
- Better alternatives:

  - Python backend service (FastAPI / Flask)
  - ONNX Runtime
  - tfjs (lightweight inference only)

No ML dependencies are auto-installed.

# 📄 `README.md` — **Java Project**

# Java Project (Plain JDK · No Maven / Gradle)

This project was generated using `new-java-project.bat`.

It intentionally uses:

- `javac` directly
- `java` runtime directly
- No build systems
- Metadata stored in `project_config.yaml`

---

## Prerequisites (install once)

### 1. JDK (Required)

Install a **JDK** (17 or 21 recommended).

Verify:

```bat
java -version
javac -version
```

If `javac` is missing, you installed only a JRE — install a full JDK.

---

## Project Structure

```
project/
│
├─ src/
│  └─ Main.java
│
├─ out/              (compiled classes)
├─ project_config.yaml
│
├─ scripts/
│  ├─ build.cmd
│  ├─ run.cmd
│  └─ clean.cmd
│
└─ .gitignore
```

---

## Build

From the project root:

```bat
scripts\build.cmd
```

This compiles:

```bat
src/Main.java → out/Main.class
```

---

## Run

```bat
scripts\run.cmd
```

This:

1. Builds (if needed)
2. Runs:

```bat
java -cp out Main
```

---

## Clean Build Output

```bat
scripts\clean.cmd
```

Removes:

```
out/
```

---

## VS Code Setup (Recommended)

Install:

- **Extension Pack for Java** (Microsoft)

Then:

1. Open the project folder
2. Restart VS Code if Java isn’t detected
3. Ensure `java` and `javac` are on PATH

---

## AI / TensorFlow Notes (`--ai`, `--tf`)

If created with `--ai` or `--tf`, notes are recorded in `project_config.yaml`.

Recommended ML strategies in Java:

- DJL (Deep Java Library)
- ONNX Runtime
- Python service for TensorFlow-heavy workloads

This template does **not** install ML dependencies.
