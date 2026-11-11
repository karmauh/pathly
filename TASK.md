# TASK.md — Aplikacja dla kurierów: rozpoznawanie adresów i optymalizacja trasy

## 1. Cel projektu

Natywna aplikacja iOS dla kuriera. Kurier robi aparatem zdjęcie listu przewozowego naklejonego na paczkę, aplikacja rozpoznaje z niego **wyłącznie adres doręczenia**, a po zebraniu wszystkich przesyłek wylicza najszybszą kolejność doręczeń, rozpoczynając i kończąc trasę w zapisanej bazie.

Projekt ma charakter **nauki i portfolio**. Liczy się czytelna architektura, zrozumiały kod i świadomie podejmowane decyzje, a nie szybkość dostarczenia funkcji.

## 2. Zasady współpracy z agentem

- Pracujesz **etapami** (sekcja 9). Nie przechodzisz do kolejnego etapu bez mojej akceptacji.
- Przed rozpoczęciem etapu krótko przedstawiasz plan: jakie pliki powstaną, jakie typy i dlaczego.
- Po zakończeniu etapu zwięźle wyjaśniasz kluczowe decyzje i fragmenty kodu, tak abym rozumiał, co i dlaczego zostało zrobione.
- Pracujesz w małych, sprawdzalnych krokach. Każdy etap kończy się projektem, który się kompiluje i uruchamia.
- Gdy wymaganie jest niejasne lub istnieje kilka sensownych rozwiązań, pytasz, zamiast zgadywać.
- Nie dodajesz zależności zewnętrznych (SPM) bez uzasadnienia i mojej zgody. Preferowane są frameworki Apple.
- Nie rozszerzasz zakresu poza ten dokument bez uzgodnienia.
- Nie wykonujesz żadnych operacji Git. Na końcu każdego etapu przygotowujesz propozycję commitów z wiadomościami w języku angielskim i gotowe komendy do skopiowania (sekcja 13).

## 3. Stos technologiczny

| Obszar | Technologia |
|---|---|
| Platforma | iOS, minimalna wersja **iOS 26** |
| Język / UI | Swift 6 (strict concurrency), SwiftUI |
| Stan | Observation (`@Observable`) |
| Persystencja | SwiftData, **tylko lokalnie** (bez kont, bez iCloud, bez backendu) |
| Aparat | AVFoundation lub `UIImagePickerController` / komponent aparatu SwiftUI |
| OCR | Vision (`RecognizeTextRequest`, język `pl-PL`) |
| Geokodowanie | MapKit (`MKGeocodingRequest`) |
| Mapa | MapKit dla SwiftUI (`Map`, `Marker`, `MapPolyline`) |
| Macierz czasów przejazdu | OpenRouteService Matrix API (profil `driving-car`) |
| Testy | Swift Testing, testy jednostkowe logiki |
| Środowisko | Xcode na MacBooku Pro M1 Pro |

## 4. Zakres funkcjonalny (MVP)

### 4.1. Baza
- W ustawieniach kurier zapisuje adres bazy (wpisany ręcznie, geokodowany i zapisany ze współrzędnymi).
- Baza jest punktem startu i końca każdej trasy.
- Bez zapisanej bazy wyliczenie trasy jest zablokowane z czytelnym komunikatem.

### 4.2. Dodawanie przesyłki ze zdjęcia
1. Kurier robi zdjęcie listu przewozowego. Jedno zdjęcie odpowiada jednej przesyłce.
2. Vision rozpoznaje tekst ze zdjęcia.
3. Parser wyodrębnia **adres doręczenia (odbiorcy)** i ignoruje nadawcę oraz pozostałe pola (kody kreskowe, numery przesyłek, wagi, uwagi).
4. Kurier widzi ekran podglądu z rozpoznanym adresem rozbitym na pola: ulica, numer budynku, numer lokalu, kod pocztowy, miejscowość. Może je poprawić i zatwierdzić albo odrzucić.
5. Po zatwierdzeniu adres jest geokodowany i zapisywany jako przystanek.
6. Możliwe jest też ręczne dodanie adresu bez zdjęcia (ten sam formularz).

### 4.3. Lista przesyłek
- Lista przesyłek bieżącej trasy z możliwością edycji i usuwania.
- Przesyłki, których nie udało się geokodować, są wyraźnie oznaczone i wymagają poprawy adresu przed wyliczeniem trasy.

### 4.4. Wyliczenie trasy
- Przycisk „Wylicz trasę” pobiera macierz czasów przejazdu, uruchamia optymalizację i zapisuje kolejność przystanków.
- Obliczenia działają w tle, interfejs pokazuje postęp i pozostaje responsywny.
- Wynik: kolejność przystanków, szacowany łączny czas przejazdu i dystans.
- Dodanie lub usunięcie przesyłki po wyliczeniu oznacza trasę jako nieaktualną i pozwala przeliczyć ją ponownie.

### 4.5. Realizacja trasy
- Widok listy kolejnych przystanków oraz widok mapy z ponumerowanymi znacznikami i linią trasy.
- Oznaczanie przystanku jako doręczony lub niedoręczony.
- Wyróżniony bieżący (następny) przystanek.
- Przycisk nawigacji otwiera trasę do przystanku w Apple Maps lub Google Maps (jeśli zainstalowane, wybór w ustawieniach).

### 4.6. Poza zakresem MVP
Okna czasowe, priorytety przesyłek, wielu kurierów i pojazdów, pojemność pojazdu, nawigacja zakręt po zakręcie w aplikacji, konta użytkowników, synchronizacja, backend, odczyt kodów kreskowych, wersja na Androida.

## 5. Rozpoznawanie adresu doręczenia

To najbardziej niepewna część projektu. Etykiety różnych przewoźników mają różny układ, dlatego parser ma być oddzielnym, testowalnym modułem, niezależnym od Vision.

Wymagania:
- Wejście parsera: lista rozpoznanych linii tekstu wraz z ich położeniem na zdjęciu (bounding box) i pewnością rozpoznania. Wyjście: struktura `ParsedAddress` z polami i oceną pewności.
- Zastosuj heurystyki:
  - kotwice odbiorcy: m.in. „Odbiorca”, „Adres doręczenia”, „Doręczyć do”, „Do:”, „Receiver”, „Recipient”, „Deliver to”, „Ship to”;
  - kotwice nadawcy do odrzucenia: m.in. „Nadawca”, „Od:”, „Sender”, „From”, „Shipper”;
  - polski kod pocztowy `\d{2}-\d{3}` jako punkt zaczepienia linii z miejscowością;
  - wzorce ulicy: prefiksy „ul.”, „al.”, „pl.”, „os.”, numer budynku i lokalu (`12`, `12A`, `12/4`, `12 m. 4`);
  - grupowanie linii według położenia na zdjęciu, aby wybrać blok odbiorcy;
  - gdy znaleziono kilka kandydatów, wybierz blok przy kotwicy odbiorcy, a w razie braku kotwic zwróć kandydatów do wyboru przez kuriera.
- Normalizacja: usuwanie zbędnych spacji, poprawa typowych błędów OCR w kodzie pocztowym (np. `O` na `0`, `l` na `1`), ujednolicenie wielkości liter.
- Parser nigdy nie zapisuje adresu bez zatwierdzenia przez kuriera (ekran podglądu z sekcji 4.2).
- Zgromadź w repozytorium zestaw anonimizowanych przykładowych tekstów z etykiet (fikcyjne dane) jako dane testowe.

## 6. Geokodowanie

- `MKGeocodingRequest` z pełnym adresem i krajem „Polska”.
- Apple ogranicza liczbę zapytań geokodujących. Zapytania wykonuj sekwencyjnie z kolejką, ponawianiem z opóźnieniem po błędzie limitu i informacją o postępie.
- Geokodowanie wykonuj od razu po zatwierdzeniu adresu, a nie dopiero przy wyliczaniu trasy, aby rozłożyć zapytania w czasie.
- Przechowuj współrzędne w modelu przesyłki i nie geokoduj ponownie niezmienionego adresu.
- Brak wyniku lub wynik niejednoznaczny: oznacz przesyłkę i pozwól kurierowi poprawić adres lub wskazać punkt na mapie.

## 7. Macierz czasów przejazdu (OpenRouteService)

- Endpoint: `POST /v2/matrix/driving-car`, metryki `duration` i `distance`.
- Ograniczenia darmowego planu, które musisz uwzględnić:
  - maksymalnie **3500 par (źródło × cel) na jedno zapytanie**;
  - **500 zapytań macierzy dziennie** i **40 na minutę**.
- Dla N punktów (przystanki + baza) pełna macierz ma N × N par, np. 101 × 101 = 10 201. Dziel ją na bloki przez parametry `sources` i `destinations` (np. 34 źródła × 101 celów = 3434 pary), składaj wynik w jedną macierz i pilnuj limitu na minutę.
- Macierz jest **asymetryczna** (czas A→B może się różnić od B→A). Algorytm musi to uwzględniać.
- Klucz API trzymaj poza repozytorium (np. plik `Secrets.xcconfig` dodany do `.gitignore`, odczyt przez `Info.plist`). Dodaj plik przykładowy `Secrets.example.xcconfig`.
- Wynik macierzy zapisuj w pamięci podręcznej dla danego zestawu punktów, aby ponowne przeliczenie bez zmian nie zużywało limitu.
- Fallback: przy braku sieci, błędzie lub wyczerpanym limicie użyj odległości w linii prostej (haversine) przeliczonej na szacowany czas i wyraźnie poinformuj kuriera, że trasa jest przybliżona.
- Całość schowaj za protokołem, np.:

```swift
protocol TravelCostProvider: Sendable {
    func costMatrix(for points: [Coordinate]) async throws -> CostMatrix
}
```

z implementacjami `OpenRouteServiceCostProvider` i `HaversineCostProvider`. Algorytm trasy zależy tylko od `CostMatrix`.

## 8. Algorytm optymalizacji trasy

Problem to asymetryczny problem komiwojażera (ATSP) z ustalonym punktem startu i końca (baza). Dijkstra nie jest tu właściwym narzędziem: wyznacza najkrótszą drogę między dwoma punktami, co robi już za nas OpenRouteService przy budowie macierzy. Dla ponad 100 przystanków dokładne rozwiązanie jest niewykonalne, dlatego stosujesz heurystyki:

1. **Konstrukcja**: najbliższy sąsiad startujący z bazy.
2. **Poprawa**: przeszukiwanie lokalne do braku poprawy lub limitu czasu:
   - **Or-opt** (przenoszenie segmentów 1–3 przystanków w inne miejsce, bez odwracania kierunku);
   - **2-opt** z pełnym przeliczeniem kosztu odwracanego segmentu (wymagane przy macierzy asymetrycznej).
3. Opcjonalnie: kilka startów z losowym zaburzeniem kolejności i wybór najlepszego wyniku.

Wymagania:
- Moduł algorytmu jest czystym Swiftem, bez zależności od UI, MapKit i sieci, w pełni testowalny.
- Obliczenia w tle (`Task`, bez blokowania głównego wątku), z obsługą anulowania i limitem czasu (np. 2 s).
- Wynik zawiera kolejność, łączny koszt oraz informację, czy użyto macierzy rzeczywistej, czy przybliżonej.
- Wydajność: dla 150 punktów wynik w czasie poniżej 2 s na iPhonie.

## 9. Architektura

- MVVM z warstwą serwisów; widoki SwiftUI bez logiki biznesowej.
- Wstrzykiwanie zależności przez protokoły (umożliwia testy i podmianę implementacji).
- Proponowana struktura:

```
App/
Features/
  Base/            ustawienia bazy
  Capture/         aparat, OCR, ekran podglądu adresu
  Parcels/         lista przesyłek
  Route/           wyliczenie trasy, lista przystanków, mapa
Domain/
  Models/          Parcel, Address, Coordinate, Route, Stop, CostMatrix
  AddressParsing/  parser adresu doręczenia
  RouteOptimization/
Services/
  TextRecognition/ Vision
  Geocoding/       MapKit
  TravelCost/      OpenRouteService, Haversine
  Navigation/      otwieranie Apple Maps / Google Maps
Persistence/       SwiftData
Tests/
```

- Model danych (SwiftData), minimum: `Base`, `Parcel` (adres, współrzędne, status geokodowania, status doręczenia, zdjęcie opcjonalnie), `Route` (data, kolejność, koszt, typ macierzy, aktualność).
- Uprawnienia: aparat i lokalizacja z opisami w `Info.plist` po polsku.
- Interfejs aplikacji w języku polskim.

## 10. Etapy realizacji

| Etap | Zakres | Kryterium ukończenia |
|---|---|---|
| 0 | Projekt Xcode, struktura katalogów, konfiguracja sekretów, cel testów | Pusta aplikacja uruchamia się, testy przechodzą |
| 1 | Modele domenowe, SwiftData, ustawienia bazy z geokodowaniem | Baza zapisuje się i jest widoczna po ponownym uruchomieniu |
| 2 | Parser adresu doręczenia z testami na danych przykładowych | Testy parsera przechodzą dla zestawu przykładów |
| 3 | Aparat i OCR, ekran podglądu i edycji adresu, ręczne dodawanie | Ze zdjęcia etykiety powstaje zatwierdzona przesyłka |
| 4 | Kolejka geokodowania przesyłek, oznaczanie błędów | Przesyłki mają współrzędne lub status błędu |
| 5 | `TravelCostProvider`: OpenRouteService z podziałem na bloki, pamięć podręczna, fallback haversine | Macierz dla ponad 100 punktów pobiera się w limitach API |
| 6 | Algorytm trasy z testami i pomiarem wydajności | Testy przechodzą, czas poniżej 2 s dla 150 punktów |
| 7 | Widok trasy: lista, mapa, statusy doręczeń, nawigacja zewnętrzna | Pełny przepływ od zdjęcia do realizacji trasy |
| 8 | Dopracowanie: obsługa błędów, stany puste, dostępność, README | Aplikacja gotowa do pokazania w portfolio |

## 11. Testy

Testy jednostkowe (Swift Testing) obejmują logikę, bez testów UI:
- parser adresu: poprawne wyodrębnienie odbiorcy, odrzucenie nadawcy, różne formaty numerów, błędy OCR w kodzie pocztowym, brak kotwic;
- podział macierzy na bloki i jej składanie (z atrapą klienta HTTP);
- algorytm trasy: poprawność permutacji (każdy przystanek dokładnie raz, start i koniec w bazie), brak pogorszenia względem trasy początkowej, poprawne liczenie kosztu przy macierzy asymetrycznej, małe przypadki porównane z rozwiązaniem optymalnym metodą brute force;
- haversine dla znanych par współrzędnych.

## 12. Definicja ukończenia projektu

- Kurier może zapisać bazę, dodać ponad 100 przesyłek ze zdjęć z weryfikacją adresu, wyliczyć trasę na rzeczywistych czasach przejazdu i zrealizować ją z listy i mapy.
- Aplikacja działa w trybie przybliżonym bez dostępu do API.
- Kod kompiluje się bez ostrzeżeń w trybie Swift 6 strict concurrency, testy przechodzą.
- README opisuje cel, architekturę, użyty algorytm, konfigurację klucza API i ograniczenia projektu.

## 13. Git i commity (GitHub)

Repozytorium jest hostowane na GitHubie. Commity wykonuję wyłącznie ja.

### 13.1. Czego nie robisz
- Nie uruchamiasz żadnych poleceń Git, które zmieniają stan repozytorium: `git add`, `git commit`, `git push`, `git merge`, `git rebase`, `git reset`, `git checkout`, `git stash`, tworzenie gałęzi ani tagów.
- Wolno Ci jedynie odczytać stan repozytorium (`git status`, `git diff`, `git log`), aby poprawnie przygotować propozycję commitów.

### 13.2. Co przygotowujesz na koniec każdego etapu
1. **Podział zmian na commity.** Każdy commit to jedna logiczna, kompletna zmiana, po której projekt się kompiluje (np. osobno modele domenowe, osobno parser, osobno jego testy, jeśli tworzą sensowne całości).
2. **Dla każdego commita:**
   - treść wiadomości commita;
   - listę plików, które mają się w nim znaleźć (pełne ścieżki względem katalogu głównego repozytorium), z oznaczeniem, czy plik jest nowy, zmieniony czy usunięty.
3. **Gotowe komendy** w jednym bloku kodu, w kolejności wykonania, do skopiowania w terminalu, np.:

```bash
git add Domain/Models/Parcel.swift Domain/Models/Address.swift Domain/Models/Coordinate.swift
git commit -m "feat(domain): add parcel, address and coordinate models" -m "Domain models independent of SwiftData and UI, used by the address parser and route optimizer."
git add Tests/AddressParsingTests/ParsedAddressTests.swift
git commit -m "test(parsing): add postal code normalization tests"
```

4. Na końcu bloku podajesz `git push` jako osobną, ostatnią komendę.

### 13.3. Format wiadomości commitów
- Konwencja **Conventional Commits**: `typ(zakres): opis`.
- Typy: `feat`, `fix`, `refactor`, `test`, `docs`, `chore`, `build`, `style`.
- Zakres odpowiada modułowi z sekcji 9, np. `domain`, `parsing`, `capture`, `geocoding`, `travel-cost`, `routing`, `route-ui`, `persistence`, `config`.
- **Wiadomości commitów piszesz wyłącznie w języku angielskim**, zarówno tytuł, jak i treść. Dotyczy to wszystkich commitów bez wyjątku, mimo że komunikacja ze mną i interfejs aplikacji są po polsku.
- Opis w trybie rozkazującym (`add`, `fix`, `remove`, nie `added`, `fixes`), małą literą, bez kropki na końcu, maksymalnie 72 znaki w pierwszej linii.
- Przy większych zmianach dodajesz treść (drugi parametr `-m`), również po angielsku, wyjaśniającą, co i dlaczego zostało zmienione.

### 13.4. Zasady dotyczące plików
- Przy każdej propozycji sprawdzasz, czy do commita nie trafiają pliki prywatne lub generowane: `Secrets.xcconfig`, `xcuserdata/`, `DerivedData/`, `.DS_Store`, `*.xcuserstate`. Muszą być w `.gitignore`, który przygotowujesz w etapie 0.
- Do repozytorium trafia `Secrets.example.xcconfig` bez prawdziwego klucza API.
- Jeśli zmiana dotyczy pliku `project.pbxproj`, dołączasz go do commita, w którym dodano odpowiadające mu pliki źródłowe.
