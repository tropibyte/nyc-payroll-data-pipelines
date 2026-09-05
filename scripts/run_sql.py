#!/usr/bin/env python3
"""
Run a .sql file against Azure SQL Database or the Synapse serverless SQL pool
using the Microsoft Entra token from your existing `az login`.

No password anywhere: the token comes from the Azure CLI's own cache, so the
SQL admin password never has to be typed, stored, or passed around. It does
require that your Entra identity is the server's Entra admin --
scripts/provision_azure.ps1 sets that up, or:

    az sql server ad-admin create -g <rg> -s <server> \
        --display-name <upn> --object-id $(az ad signed-in-user show --query id -o tsv)

Usage:
    python scripts/run_sql.py sql/01_sqldb_create_tables.sql
    python scripts/run_sql.py sql/04_verification_queries.sql
    python scripts/run_sql.py sql/rendered/03_synapse_external_table.sql --synapse

Batches are split on lines containing only GO, the same way sqlcmd does it.
"""

import argparse
import json
import pathlib
import re
import struct
import subprocess
import sys

import pyodbc

SQL_COPT_SS_ACCESS_TOKEN = 1256
ROOT = pathlib.Path(__file__).resolve().parent.parent
CFG = json.loads((ROOT / "config" / "project.json").read_text(encoding="utf-8"))


def token_attrs():
    tok = subprocess.run(
        ["az", "account", "get-access-token",
         "--resource", "https://database.windows.net/",
         "--query", "accessToken", "-o", "tsv"],
        capture_output=True, text=True, shell=True,
    )
    if tok.returncode != 0:
        sys.exit(f"could not get a token -- is `az login` current?\n{tok.stderr}")
    raw = tok.stdout.strip().encode("utf-16-le")
    return {SQL_COPT_SS_ACCESS_TOKEN: struct.pack("=i", len(raw)) + raw}


def driver():
    installed = [d for d in pyodbc.drivers() if "ODBC Driver" in d and "SQL Server" in d]
    if not installed:
        sys.exit("no 'ODBC Driver NN for SQL Server' found")
    # Prefer the newest numbered driver available.
    return sorted(installed, key=lambda d: int(re.search(r"\d+", d).group()))[-1]


def split_batches(text):
    """Split on GO the way sqlcmd does -- but only on a GO that is actually
    code. A GO inside a /* ... */ block is documentation, and treating it as a
    separator chops the comment into fragments that then fail to parse."""
    parts, cur, depth = [], [], 0
    for line in text.splitlines():
        stripped = line.strip()
        if depth == 0 and stripped.upper() == "GO":
            if any(l.strip() for l in cur):
                parts.append("\n".join(cur))
            cur = []
            continue
        cur.append(line)
        # Count block-comment nesting on this line, ignoring -- line comments.
        code = line.split("--", 1)[0]
        depth += code.count("/*") - code.count("*/")
        depth = max(depth, 0)
    if any(l.strip() for l in cur):
        parts.append("\n".join(cur))
    return parts


def show(cur):
    """Print every result set a batch produced, as an aligned table."""
    while True:
        if cur.description:
            cols = [c[0] for c in cur.description]
            rows = cur.fetchall()
            widths = [
                max(len(c), *(len(str(r[i])) for r in rows)) if rows else len(c)
                for i, c in enumerate(cols)
            ]
            print("  " + "  ".join(c.ljust(w) for c, w in zip(cols, widths)))
            print("  " + "  ".join("-" * w for w in widths))
            for r in rows:
                print("  " + "  ".join(str(v).ljust(w) for v, w in zip(r, widths)))
            print(f"  ({len(rows)} row{'s' if len(rows) != 1 else ''})\n")
        if not cur.nextset():
            break


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("file")
    ap.add_argument("--synapse", action="store_true",
                    help="target the Synapse serverless SQL pool instead of Azure SQL DB")
    ap.add_argument("--database")
    ap.add_argument("--stop-on-error", action="store_true")
    args = ap.parse_args()

    if args.synapse:
        server = f"{CFG['synapseWorkspace']}-ondemand.sql.azuresynapse.net"
        database = args.database or CFG["synapseDatabase"]
    else:
        server = f"{CFG['sqlServer']}.database.windows.net"
        database = args.database or CFG["sqlDatabase"]

    conn_str = (
        f"Driver={{{driver()}}};Server=tcp:{server},1433;Database={database};"
        "Encrypt=yes;TrustServerCertificate=no;Connection Timeout=60;"
    )
    print(f"-> {server} / {database}\n")

    path = pathlib.Path(args.file)
    if not path.is_absolute():
        path = ROOT / path
    batches = split_batches(path.read_text(encoding="utf-8"))

    failed = 0
    with pyodbc.connect(conn_str, attrs_before=token_attrs(), autocommit=True) as conn:
        for i, batch in enumerate(batches, 1):
            first = next((l.strip() for l in batch.splitlines()
                          if l.strip() and not l.strip().startswith("--")), "")
            label = (first[:70] + "...") if len(first) > 70 else first
            try:
                cur = conn.cursor()
                cur.execute(batch)
                print(f"[{i}/{len(batches)}] ok  {label}")
                show(cur)
            except Exception as e:
                failed += 1
                print(f"[{i}/{len(batches)}] ERR {label}\n      {e}\n", file=sys.stderr)
                if args.stop_on_error:
                    break

    if failed:
        sys.exit(f"{failed} batch(es) failed")
    print("all batches succeeded")


if __name__ == "__main__":
    main()
