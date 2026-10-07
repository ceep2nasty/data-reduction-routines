# 1D fiber-optic workflows

- `cos_basis/`: cosine ROI selection, center finding, linearity checks,
  membrane/bending decomposition, empirical reconstruction, and JSON outputs.
- `sine_basis/`: sine shape reconstruction, run inspection, and tare inspection.

Shared `load_fos_case.py` and `shift_to_strain.py` remain in `subroutines/`.
Scripts can be run directly from the repository root, for example:

```powershell
.\.venv\Scripts\python.exe workflows/fiber_optic/subroutines/1D/cos_basis/reconstruct_cos_basis_v2.py
```

Cosine ROI JSON and generated reconstruction/decomposition JSON stay beside
their scripts. Report figures continue to use the configured external report folder.
