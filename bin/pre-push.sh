#!/bin/sh
# Garde-fou anti écran blanc : l'app est un index.html compilé par Babel dans le navigateur,
# donc une erreur JSX casse TOUTE l'application en production. On refuse le push si ça ne
# compile pas, ou si les tests de la logique Agence échouent.
# Contournement exceptionnel : git push --no-verify
cd "$(git rev-parse --show-toplevel)" || exit 1
[ -f tests/check-babel.mjs ] || exit 0

printf 'pre-push · compilation JSX... '
if ! out=$(node tests/check-babel.mjs 2>&1); then
  printf '\n\n❌ PUSH REFUSÉ — index.html ne compile pas (écran blanc garanti en prod) :\n%s\n\n' "$out"
  exit 1
fi
printf 'OK\n'

if [ -f tests/agence-calc.test.mjs ]; then
  printf 'pre-push · tests agence-calc... '
  if ! out=$(node --test tests/agence-calc.test.mjs 2>&1); then
    printf '\n\n❌ PUSH REFUSÉ — tests en échec :\n%s\n\n' "$(printf '%s' "$out" | tail -25)"
    exit 1
  fi
  printf 'OK\n'
fi
exit 0
