# pr_gestionale

Gestionale per la **gestione documentale** di un'azienda: anagrafiche, fatture,
DDT/bolle di accompagnamento e catalogo articoli.
Il progetto nasce dalla conversione del foglio Excel `gestione_documenti_libera.xlsx`
(fogli *Destinatari, Fattura elettronica, Bolla di accompagnamento, Documento di
trasporto, Database utenti, Liste*) in un database relazionale MySQL/MariaDB.

## Contenuto della cartella

```
pr_gestionale/
├── db/
│   └── gestionale.sql   # Schema + vincoli + dati di esempio + viste (MySQL 8 / MariaDB 10.5+)
├── .gitignore
└── README.md
```

`db/gestionale.sql` crea il database `gestione_documenti` (InnoDB, `utf8mb4`) con
tabelle, vincoli di integrità, dati di decodifica, dati di esempio e viste.

## Modello dati (dal dump)

**Tabelle di decodifica** — ex foglio "Liste", alimentano i menu a tendina:
`unita_misura`, `tipo_documento_sdi`, `aliquota_iva`, `modalita_pagamento`,
`causale_trasporto`, `trasporto_a_cura`, `porto`, `regime_fiscale`, `natura_iva`.

**Anagrafiche**
- `azienda` — mittente/cedente: ragione sociale, P.IVA, CF, sede, `regime_fiscale`, IBAN, PEC
- `cliente` — destinatario: P.IVA/CF, sede, `codice_sdi`, PEC, `indirizzo_consegna`
- `articolo` — catalogo beni/servizi: `tipo` (BENE/SERVIZIO), UM, prezzo, aliquota IVA, `attivo`

**Documenti**
- `fattura` + `fattura_riga` — testata e righe; `numero` e `data_scadenza` sono
  colonne generate, `imponibile`/`importo_iva` calcolati per riga
- `documento_trasporto` + `documento_trasporto_riga` — DDT e bolle in un'unica
  tabella, distinte dal campo `tipo` (`DDT`/`BOLLA`); `numero` generato in base al tipo

**Viste**
- `v_destinatario` — scheda cliente con luogo di consegna (alternativo o da sede)
- `v_fattura_riepilogo_iva` — imponibile e imposta raggruppati per aliquota
- `v_fattura_totali` — testata, totali (imponibile + IVA + bollo) e riferimenti DDT
- `v_documento_trasporto` — testata DDT/bolla con causale, porto, vettore e rif. fattura

## Cosa si potrebbe fare, basandosi sul dump

### Anagrafiche (tabelle `azienda`, `cliente`, `articolo`)
- CRUD su azienda, clienti e articoli con la validazione già prevista dai CHECK
  (P.IVA `^[0-9]{11}$`, codice SDI di 7 caratteri, prezzi/quantità non negativi)
- Ricerca cliente per `ragione_sociale` (univoca) o `partita_iva` (indicizzata)
- Gestione `indirizzo_consegna` alternativo, sfruttato da `v_destinatario`
- Disattivazione articoli tramite il flag `attivo` senza cancellarli

### Fatturazione (`fattura`, `fattura_riga`, `v_fattura_*`)
- Numerazione automatica per `azienda_id` + `anno` + `progressivo` (vincolo univoco)
- Compilazione righe con `articolo_codice`, quantità, prezzo, sconto %, aliquota
- Calcolo automatico di imponibile/IVA e totale documento dalle colonne generate
- Gestione `tipo_documento` (TD01, TD02, TD04, TD05, TD24) e `natura_iva` per lo 0%
- Scadenza calcolata da `data_emissione` + `giorni_pagamento`, bollo (0 o 2,00)
- Riepilogo IVA per fattura con `v_fattura_riepilogo_iva`
- Note di credito/debito e fatture differite: già previste le codifiche TD04/TD05/TD24

### Documenti di trasporto (`documento_trasporto`, `documento_trasporto_riga`)
- Emissione DDT e bolle con numerazione separata per `tipo`
- Dati trasporto: `causale`, `trasporto_a_cura`, `porto`, `vettore`, `numero_colli`,
  `peso_lordo_kg`, `aspetto_esteriore`, `inizio_trasporto`, `note_lotto` sulle righe
- Collegamento DDT → fattura via `fattura_id` (visibile in `v_fattura_totali.riferimento_ddt`)
- Luogo di destinazione opzionale: se NULL viene preso da `v_destinatario`
- Base per la fattura differita TD24 partendo dai DDT collegati

### Report e controllo (dalle viste esistenti)
- Riepilogo IVA per aliquota e per periodo (liquidazione)
- Totali per fattura, elenco fatture per cliente e per data (`idx_fattura_data`)
- Elenco DDT/bolle per cliente o per fattura (`idx_dt_cliente`, `idx_dt_fattura`)
- Riferimenti incrociati fattura ↔ DDT tramite le viste

### Interfaccia applicativa da costruire sopra il dump
- Form di inserimento guidati dai menu a tendina delle tabelle di decodifica
- Ricerche/filtri sfruttando gli indici già definiti (P.IVA cliente, data fattura, FK)
- Stampe/PDF di fatture e DDT partendo dalle viste di testata
- Export CSV/Excel delle viste di riepilogo

## Limiti attuali del dump (da colmare per un gestionale completo)

Il dump copre anagrafiche e documenti, ma **non** contiene ancora:
- utenti/login e ruoli (il foglio "Database utenti" è usato solo come anagrafica clienti)
- stato di pagamento/incassi (esiste la scadenza, non il saldato/residuo)
- giacenze di magazzino e movimenti
- una tabella/sequenza dedicata alla numerazione (i progressivi vanno calcolati applicativamente)
- campi completi per l'XML SDI (restano solo `codice_sdi`, `pec`, codici TD/MP/RF/N)
- log/audit delle modifiche

Queste aree richiederebbero nuove tabelle prima di poter essere implementate.

## Import del database

```bash
mysql -u root -p < db/gestionale.sql
```

In alternativa, eseguire `db/gestionale.sql` da un client grafico (DBeaver,
phpMyAdmin, HeidiSQL). Motore consigliato: MySQL 8 o MariaDB 10.5+.
