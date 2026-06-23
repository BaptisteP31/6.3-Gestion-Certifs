# Notes de vérification

## Source inspectée

- Fichier principal identifié : `claude/claude_v2.tex`.
- PDF source présent : `claude/claude_v2.pdf`.
- Images source présentes : `claude/images/revoked_rsa_chrome.png` et `claude/images/revoked_rsa_firefox.png`.
- Aucun fichier `.bib`, `.sty`, `.cls` ou annexe LaTeX séparée n'a été trouvé dans `claude/`.

## Points conservés

- Les commandes OpenSSL, PowerShell et shell reprises dans `main.tex` ont été conservées telles quelles depuis le rapport source.
- Les sorties techniques reprises ont conservé les mêmes valeurs : numéros de série, dates, statuts OCSP/CRL, tailles de clés, noms d'AC, chemins et hash/algorithmes affichés.
- Aucune clé privée, aucun PIN et aucun secret de token n'a été ajouté.
- Les deux images nécessaires au rendu de la figure sur le certificat révoqué ont été copiées dans `opencode/figures/`.

## Manques ou exécutions non prouvées dans le rapport source

- Les fichiers `isrg-1.crt` et `isrg-2.crt` sont indiqués comme absents ; l'analyse des racines ISRG n'est donc pas prouvée.
- L'échange S/MIME avec un autre groupe reste à compléter ; seule une démonstration locale est documentée.
- Les manipulations Windows, le magasin de certificats, ADCS et le certificat TLS Windows sont décrits comme procédures à exécuter, sans preuve d'exécution.
- Le rapport source mentionne des fichiers de configuration complets fournis dans une archive jointe, mais ils ne sont pas présents dans `claude/`.

## Incohérences ou points ambigus du rapport source

- Le rapport source indique en conclusion que les captures navigateur de `revoked-rsa-dv.ssl.com` restent à compléter, alors que deux captures existent et sont incluses pour Chrome/Chromium et Firefox. Le point restant semble être le troisième navigateur demandé.
- La capture pour `wrong.host.badssl.com` est mentionnée comme manquante.
