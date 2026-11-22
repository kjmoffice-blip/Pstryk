# Pstryk

Aplikacja macOS w pasku menu: kliknięcie niebieskiego aparatu zapisuje cały ekran
z kursorem myszy wskazującym monitor jako PNG w Pobranych. Kursor nie trafia do
obrazu. Aparat czerwienieje w trakcie zapisu; wraca do niebieskiego po sukcesie.
Błąd pozostawia czerwony aparat i opis w dymku. Pliki mają unikalne nazwy i są
zapisywane atomowo, bez nadpisywania wcześniejszych zrzutów.

Prawy klik lub Control+klik udostępnia autostart i zakończenie. Autostart jest
rejestrowany przy pierwszym uruchomieniu z `/Applications` lub `~/Applications`;
wyłączenie go jest zapamiętane. Nie ma okna, dźwięku, edytora ani harmonogramu.
Program działa lokalnie, bez kont, telemetrii i sieci.

## Wymagania i budowanie

macOS 14+, Xcode Command Line Tools z kompilatorem Swift i SDK macOS 14+ oraz
Python 3 do uruchomienia skryptu budującego. Aplikacja jest natywna: AppKit,
ImageIO, ServiceManagement i systemowe `screencapture`; bez bibliotek zewnętrznych.
Ikony są rysowane w kodzie.

```sh
python3 tools/build.py
open dist/Pstryk-1.0.1/Pstryk.app
```

Powstaje `.app` Universal (arm64 i x86_64), domyślnie z podpisem ad hoc. Skrypt
odmawia nadpisania istniejącej aplikacji. Do ponownego testu użyj świeżej kopii
repozytorium. Opcjonalny `PSTRYK_SIGN_IDENTITY` wybiera własną tożsamość z Pęku
kluczy; nie umieszczaj certyfikatów ani sekretów w repozytorium.

Pierwszy zrzut wymaga zgody na nagrywanie ekranu. Po zmianie zgody uruchom program
ponownie. Chronione treści mogą być puste. macOS kontroluje zgodę i autostart.

```sh
python3 tools/audit.py dist/Pstryk-1.0.1/Pstryk.app build/audit.json
```

Opcjonalna próba `Pstryk.app/Contents/MacOS/Pstryk --verify KATALOG` wykonuje
rzeczywiste zrzuty do wskazanego katalogu i wymaga uprawnień ekranu. Nie nadaje
automatycznie zgód. Nie publikuj jej obrazów. `--verify-login` zmienia rejestrację
autostartu na czas próby i nie jest potrzebny do podstawowej kontroli budowania.

Pakowanie DMG: w osobnym środowisku Python zainstaluj
`python3 -m pip install -r tools/requirements-package.txt`, następnie uruchom
`python3 tools/package.py`. `python3 tools/package.py --sources` tworzy archiwum
publicznych źródeł. Skrypty nie wykonują notaryzacji.

## Weryfikacja

Wyniki bieżącej kontroli publikowanych źródeł: `VERIFICATION.md`.
Nie potwierdzano ponownie uprawnień ekranu, autostartu ani wielu monitorów.
Licencja MIT jest w `LICENSE` i `LICENSE.txt`.

## Publikacja i prawa

Repozytorium zawiera źródła i narzędzia deweloperskie. Nie zawiera instalatora,
certyfikatów, kluczy, prywatnych zrzutów ani nagrań. Kod aplikacji jest udostępniony na licencji **MIT** (`LICENSE`).
Informacje o prawach i zależnościach: `RIGHTS.md`.

Wcześniejsze wydanie binarne 1.0.1 było podpisane Developer ID i uzyskało
notaryzację Apple w październiku 2026. To informacja historyczna, która nie
obejmuje nowych lokalnych kompilacji z tego repozytorium. Lokalna kompilacja
nie jest automatycznie podpisana Developer ID ani notaryzowana. Publiczna
publikacja kodu 22.11.2026 nie zmienia funkcji, wyglądu ani wersji aplikacji.
