# Weryfikacja — 22.11.2026

Środowisko: macOS 26.7.1, Apple Silicon, Apple Swift 6.4.

- Zbudowano z opublikowanych źródeł Universal arm64/x86_64, minimum macOS 14.
- `tools/audit.py`: poprawny podpis ad hoc, obie architektury, zależności systemowe.
- Zweryfikowano składnię skryptów Python i integralność archiwum źródeł.
- Kod Swift aplikacji odpowiada zachowanym źródłom 1.0.1; zmiany dotyczą licencji,
  dokumentacji i pakowania bez prywatnych historycznych raportów.

Systemowy `iconutil` wymagał uruchomienia poza sandboxem narzędzia testowego.
Nie wykonano ponownie rzeczywistych zrzutów, autostartu i testu wielu monitorów.
Nie wykonano nowej notaryzacji ani testu na fizycznym Macu Intel. Nowa lokalna
kompilacja ma podpis ad hoc. Wcześniejsza notaryzacja dotyczyła wydania binarnego.
