# Objective Names

Objective name and slug handling shared by objective procedures.

## Slugify

Lowercase; replace `/` and whitespace with `-`; strip non-alphanumeric characters except `-`.

Collapsing whitespace to `-` is intentional, aligning with the objective entry convention where
slugs use hyphens for spaces. Slug inputs are jj bookmark names, which rarely contain whitespace, so
the practical effect is negligible.

## Extract Objective Slug

Strip `YYYY-MM-DD-HHMM-` from an objective entry name.

## Entry Names

Objective entries use `<YYYY-MM-DD-HHMM>-<slug>`.
