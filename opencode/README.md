# Rapport LaTeX opencode

Cette version est une réécriture du rapport présent dans `claude/`. Les commandes, sorties et valeurs techniques ont été conservées, tandis que la structure et le thème LaTeX ont été changés.

## Compilation

Depuis ce dossier :

```sh
make pdf
```

Le `Makefile` essaie `latexmk -pdf main.tex`. Si `latexmk` n'est pas disponible, lancer :

```sh
pdflatex main.tex
pdflatex main.tex
```

Le PDF attendu est `main.pdf`.

## Fichiers

- `main.tex` : rapport LaTeX réécrit.
- `figures/` : captures copiées depuis `claude/images/` et utilisées par le rapport.
- `NOTES-VERIFICATION.md` : points contrôlés et limites relevées.
- `Makefile` : cibles `pdf` et `clean`.
