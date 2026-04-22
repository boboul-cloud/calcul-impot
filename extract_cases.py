"""Extract all 2042 cerfa boxes from OpenFisca-France, including dict-form fields."""
import json
import re
from openfisca_france import FranceTaxBenefitSystem

tbs = FranceTaxBenefitSystem()
seen = {}  # case -> dict

CASE_RE = re.compile(r"^[0-9][A-Z0-9]{1,4}$")

def add(code, variable, libelle, reference):
    code = code.strip().upper()
    if not CASE_RE.match(code):
        return
    if code in seen:
        return
    seen[code] = {
        "case": code,
        "variable": variable,
        "libelle": libelle,
        "reference": reference,
    }

for name, var in tbs.variables.items():
    cerfa = getattr(var, "cerfa_field", None)
    if not cerfa:
        continue
    libelle = (var.label or "").strip() or name
    ref = None
    refs = getattr(var, "reference", None)
    if isinstance(refs, str):
        ref = refs
    elif isinstance(refs, (list, tuple)) and refs:
        ref = refs[0] if isinstance(refs[0], str) else None

    if isinstance(cerfa, str):
        add(cerfa, name, libelle, ref)
    elif isinstance(cerfa, dict):
        # Could be {year: code} or {role: code} or nested
        for v in cerfa.values():
            if isinstance(v, str):
                add(v, name, libelle, ref)
            elif isinstance(v, dict):
                for vv in v.values():
                    if isinstance(vv, str):
                        add(vv, name, libelle, ref)

out = sorted(seen.values(), key=lambda d: d["case"])
print(f"Total cases: {len(out)}")
print("5N*:", [c["case"] for c in out if c["case"].startswith("5N")])
print("5K*:", [c["case"] for c in out if c["case"].startswith("5K")])

with open("calcul de l'impot/cases_2042.json", "w", encoding="utf-8") as f:
    json.dump(out, f, ensure_ascii=False, indent=2)
