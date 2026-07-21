# Lootmaster

- WOW Addon für 3.3.5
- optimiert für Rising Gods und den deutschen Client
- Tester für englischen Client gesucht

# Funktionen
## Allgemein
- Übersicht über die Rolls zu einem Item aus einer Raidwarning (Fokus Roll, Main Roll, Second Roll)
  - Rolls werden bis zu 5 Minuten lang aufgezeichnet
  - Rolls werden nach einer Minute Gelb
  - Rolls werden nach zwei Minuten rot
  - Für jeden Roll ist ein Timestamp vorhanden
  - Mehrfachrolls werden gekennzeichnet
  - Rolls können über das Kontextmenü bearbeitet werden (verschieben, löschen, als gewinner markieren)
- Wunschliste mit Visual und optionalem Sound Effekt, wenn ein betroffenes Items verrollt wird.
  - Wunschliste ist Charakter-spezifisch
- BOEs werden ebenfalls unterstützt.
- Addon wird sichtbar wenn
  - /slm in den chat eingeben wird
  - ein Item von der Wunschliste in der Raidwarning geposted wird
  - je nach Einstellung: ein Item in der Raidwarning geposted wird
## Für Raidleads / Plündermeister
- Automatischer Gruppeninvite über ein selbst festgelegtes Keyword
- Automatische Zuweisung von Loot / Splitter bzw. Fragmente an die verantwortlichen Spieler
  - Wird nach mit dem Invite zu einem Schlachtzug zurückgesetzt, damit nicht versehentlich die Items falsch zugewiesen werden.
- Erleichteres Posten von Loot über Tastenkombination + Klick auf Item (STRG+ALT+Rechtsklick)
  -  Optional mit Item Stats (Item Slot, Art, Main-Stats)
  -  "BOE" Zusatz
- Dem Gewinner wird innerhalb von 5 Minuten automatisch das Item ins Handelsfenster gelegt
  - Wird das Item automatisch gehandelt, so wird protokolliert, an welche Person das Item gehandelt wurde.
- Whisper Commands durch fremde Spieler
  - Optional: Mit "!assi" können Mitspieler sich Assistenzsrechte anfordern
  - Optional: Mit "!keinassi" können Mitspieler sich Assistenzsrechte wegnehmen
  - Mit "!pm" wechselt die Lootmethode zum Plündermeister. Raidlead wird PM
  - Mit "!pm me" wechselt die Lootmethode zu Plündermeister. Person wird zum PM nachdem der Raidlead es bestätigt.
  - Mit "!group" wechselt die Lootmethode zu Plündern als Gruppe. Erfodert die Bestätigung des Raidleads.

# Sonstiges
- Das Addon wurde im Juli 2027 fast vollständig mit Hilfe von KI entwickelt. Der Code wurde nicht gereviewed und es wurde keine Rücksicht auf die Code Qualität genommen.
- Neue Funktionen sind aktuell nicht geplant.
- Abgelehnte Funktionen
  - Elvui Skin: Für die meisten Anwender zu kompliziert zum Aktivieren, da für die Integration auch das ElvUI Addon aktualisiert werden muss.
