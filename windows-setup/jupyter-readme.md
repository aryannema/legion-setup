Assumptions (your chosen layout):

- Projects live in: **`D:\dev\projects\`**
- Tools live in: **`D:\dev\tools\`**
- Caches live in: **`D:\dev\cache\`**
- You want Jupyter to run **standalone in browser** (no VS Code)

# A) One-time setup (done once per machine)

## A1) Create a dedicated conda environment for Jupyter

**Run in CMD** (any folder is fine, but I’ll show it explicitly):

**Location:** `C:\Users\aarya>` (or anywhere)

```bat
conda create -n jupyter python=3.11 -y
```

Now activate it:

**Location:** `C:\Users\aarya>` (or anywhere)

```bat
conda activate jupyter
```

---

## A2) Install Jupyter using uv inside that conda env

**Location:** anywhere, but you must have `jupyter` env active

```bat
uv pip install jupyterlab notebook ipykernel
```

Verify:

```bat
python -m jupyter --version
```

At this point, Jupyter is installed **inside** the conda env `jupyter`.

---

## A3) Optional but recommended: set pnpm store to D:\dev\cache (unrelated to Jupyter, but matches your layout)

**Location:** anywhere

```bat
pnpm config set store-dir D:\dev\cache\pnpm-store
pnpm config get store-dir
```

---

## A4) Optional convenience: create a launcher CMD file (no PowerShell)

Create a file at:

✅ **`D:\dev\tools\bin\jupyter-projects.cmd`**

Put this content inside it:

```bat
@echo off
setlocal
call conda activate jupyter
cd /d D:\dev\projects
python -m jupyter lab
```

Now you can start Jupyter by typing `jupyter-projects` from anywhere.

---

# B) Daily use workflow (what you do every time)

## B1) Activate the Jupyter env

**Location:** anywhere, example shown:

**Location:** `C:\Users\aarya>`

```bat
conda activate jupyter
```

---

## B2) Move to your projects directory

**Location:** after activation:

```bat
cd /d D:\dev\projects
```

Now your working directory is:

✅ **`D:\dev\projects\`**

---

## B3) Launch JupyterLab in the browser

**Location:** `D:\dev\projects\`

```bat
python -m jupyter lab
```

This will start a local server and open a URL like:

- `http://localhost:8888/lab`

Your notebook file browser will show the contents of:

✅ **`D:\dev\projects\`**

---

# C) Installing packages for notebooks (conda + uv rule)

Whenever you want additional Python packages available in notebooks, you install them into the **same env** and then restart the notebook kernel.

## C1) Activate env

**Location:** anywhere

```bat
conda activate jupyter
```

## C2) Install packages via uv

**Location:** anywhere (doesn’t matter), but env must be active:

Example packages:

```bat
uv pip install numpy pandas matplotlib
```

Example ML stack:

```bat
uv pip install scikit-learn
```

Verify a package is installed:

```bat
python -c "import numpy; print(numpy.__version__)"
```

---

# D) Confirm you’re using the correct Python inside the notebook

In a notebook cell, run:

```python
import sys
sys.executable
```

It should point to something like:

- `...\Miniconda3\envs\jupyter\python.exe`

That confirms the notebook kernel is using the `jupyter` conda env.

---

# E) Full “copy/paste” quick sequence (start to finish)

### Start Jupyter

**Location:** anywhere

```bat
conda activate jupyter
cd /d D:\dev\projects
python -m jupyter lab
```

### Install a package then use it

**Location:** anywhere

```bat
conda activate jupyter
uv pip install numpy
```

Then in notebook:

```python
import numpy as np
np.__version__
```

---

# Notes (important)

## 1) Why `python -m jupyter` instead of `jupyter`

`python -m jupyter lab` guarantees you run the Jupyter belonging to the currently active environment. This avoids PATH issues entirely.

## 2) One env vs per-project env

This workflow uses **one shared env (`jupyter`)** so Jupyter is always ready for notebooks under `D:\dev\projects`.
If you later want per-project isolation (each project has its own env + kernel), tell me and I’ll give that exact workflow too—still conda + uv.
