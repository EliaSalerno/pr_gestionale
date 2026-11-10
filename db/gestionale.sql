-- =====================================================================
--  DATABASE: gestione_documenti
--  Origine : gestione_documenti_libera.xlsx
--            (Destinatari, Fattura elettronica, Bolla di accompagnamento,
--             Documento di trasporto, Database utenti, Liste)
--  Motore  : MySQL 8 / MariaDB 10.5+  (InnoDB, utf8mb4)
--  Uso     : mysql -u root -p < gestione_documenti_dump.sql
-- =====================================================================

DROP DATABASE IF EXISTS gestione_documenti;
CREATE DATABASE gestione_documenti
  CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE gestione_documenti;

SET FOREIGN_KEY_CHECKS = 0;

-- =====================================================================
-- 1. TABELLE DI DECODIFICA  (foglio "Liste": alimentano i menu a tendina)
-- =====================================================================

CREATE TABLE unita_misura (
  codice       VARCHAR(5)   NOT NULL,
  descrizione  VARCHAR(50)  NOT NULL,
  PRIMARY KEY (codice)
) ENGINE=InnoDB;

CREATE TABLE tipo_documento_sdi (
  codice       CHAR(4)      NOT NULL,            -- TD01, TD02, ...
  descrizione  VARCHAR(80)  NOT NULL,
  PRIMARY KEY (codice)
) ENGINE=InnoDB;

CREATE TABLE aliquota_iva (
  aliquota     DECIMAL(5,2) NOT NULL,            -- in percentuale: 22.00, 10.00 ...
  descrizione  VARCHAR(50)  NOT NULL,
  PRIMARY KEY (aliquota)
) ENGINE=InnoDB;

CREATE TABLE modalita_pagamento (
  codice       CHAR(4)      NOT NULL,            -- MP01, MP05, ...
  descrizione  VARCHAR(50)  NOT NULL,
  PRIMARY KEY (codice)
) ENGINE=InnoDB;

CREATE TABLE causale_trasporto (
  id           TINYINT UNSIGNED NOT NULL AUTO_INCREMENT,
  descrizione  VARCHAR(50)  NOT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_causale (descrizione)
) ENGINE=InnoDB;

CREATE TABLE trasporto_a_cura (
  id           TINYINT UNSIGNED NOT NULL AUTO_INCREMENT,
  descrizione  VARCHAR(30)  NOT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_trasp_cura (descrizione)
) ENGINE=InnoDB;

CREATE TABLE porto (
  id           TINYINT UNSIGNED NOT NULL AUTO_INCREMENT,
  descrizione  VARCHAR(30)  NOT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_porto (descrizione)
) ENGINE=InnoDB;

CREATE TABLE regime_fiscale (
  codice       CHAR(4)      NOT NULL,            -- RF01, RF19, ...
  descrizione  VARCHAR(50)  NOT NULL,
  PRIMARY KEY (codice)
) ENGINE=InnoDB;

CREATE TABLE natura_iva (
  codice       VARCHAR(6)   NOT NULL,            -- N1, N2.1, N6.3, ...
  descrizione  VARCHAR(100) NOT NULL,
  PRIMARY KEY (codice)
) ENGINE=InnoDB;

-- =====================================================================
-- 2. ANAGRAFICHE
-- =====================================================================

-- "I TUOI DATI (mittente / cedente)" - foglio Destinatari, sezione 2
CREATE TABLE azienda (
  id                INT UNSIGNED NOT NULL AUTO_INCREMENT,
  ragione_sociale   VARCHAR(150) NOT NULL,
  partita_iva       CHAR(11)     NOT NULL,
  codice_fiscale    VARCHAR(16)  NOT NULL,
  indirizzo         VARCHAR(150) NOT NULL,
  cap               CHAR(5)      NOT NULL,
  citta             VARCHAR(80)  NOT NULL,
  provincia         CHAR(2)      NOT NULL,
  regime_fiscale    CHAR(4)      NOT NULL,
  iban              VARCHAR(34)  DEFAULT NULL,
  telefono          VARCHAR(30)  DEFAULT NULL,
  email_pec         VARCHAR(150) DEFAULT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_azienda_piva (partita_iva),
  CONSTRAINT fk_azienda_regime FOREIGN KEY (regime_fiscale)
    REFERENCES regime_fiscale (codice),
  CONSTRAINT ck_azienda_piva CHECK (partita_iva REGEXP '^[0-9]{11}$')
) ENGINE=InnoDB;

-- foglio "Database utenti" (clienti / destinatari)
CREATE TABLE cliente (
  id                  INT UNSIGNED NOT NULL AUTO_INCREMENT,
  ragione_sociale     VARCHAR(150) NOT NULL,           -- chiave di ricerca (univoca)
  partita_iva         CHAR(11)     DEFAULT NULL,
  codice_fiscale      VARCHAR(16)  DEFAULT NULL,
  indirizzo           VARCHAR(150) NOT NULL,
  cap                 CHAR(5)      NOT NULL,
  citta               VARCHAR(80)  NOT NULL,
  provincia           CHAR(2)      NOT NULL,
  codice_sdi          CHAR(7)      NOT NULL DEFAULT '0000000',
  pec                 VARCHAR(150) DEFAULT NULL,
  email               VARCHAR(150) DEFAULT NULL,
  telefono            VARCHAR(30)  DEFAULT NULL,
  indirizzo_consegna  VARCHAR(250) DEFAULT NULL,       -- "se diverso" dalla sede
  PRIMARY KEY (id),
  UNIQUE KEY uq_cliente_ragsoc (ragione_sociale),
  KEY idx_cliente_piva (partita_iva),
  CONSTRAINT ck_cliente_piva CHECK (partita_iva IS NULL OR partita_iva REGEXP '^[0-9]{11}$'),
  CONSTRAINT ck_cliente_sdi  CHECK (CHAR_LENGTH(codice_sdi) = 7)
) ENGINE=InnoDB;

-- catalogo articoli / servizi (codici usati nelle righe dei documenti)
CREATE TABLE articolo (
  codice            VARCHAR(20)  NOT NULL,
  descrizione       VARCHAR(255) NOT NULL,
  tipo              ENUM('BENE','SERVIZIO') NOT NULL DEFAULT 'BENE',
  um                VARCHAR(5)   NOT NULL,
  prezzo_unitario   DECIMAL(12,4) NOT NULL DEFAULT 0,
  aliquota_iva      DECIMAL(5,2) NOT NULL DEFAULT 22.00,
  attivo            TINYINT(1)   NOT NULL DEFAULT 1,
  PRIMARY KEY (codice),
  CONSTRAINT fk_articolo_um  FOREIGN KEY (um) REFERENCES unita_misura (codice),
  CONSTRAINT fk_articolo_iva FOREIGN KEY (aliquota_iva) REFERENCES aliquota_iva (aliquota),
  CONSTRAINT ck_articolo_prezzo CHECK (prezzo_unitario >= 0)
) ENGINE=InnoDB;

-- =====================================================================
-- 3. FATTURA  (foglio "Fattura elettronica")
-- =====================================================================

CREATE TABLE fattura (
  id                    INT UNSIGNED NOT NULL AUTO_INCREMENT,
  azienda_id            INT UNSIGNED NOT NULL,           -- cedente/prestatore
  cliente_id            INT UNSIGNED NOT NULL,           -- cessionario/committente
  anno                  SMALLINT UNSIGNED NOT NULL,
  progressivo           INT UNSIGNED NOT NULL,
  numero                VARCHAR(20)  GENERATED ALWAYS AS
                          (CONCAT(anno, '/', LPAD(progressivo, 3, '0'))) STORED,
  tipo_documento        CHAR(4)      NOT NULL DEFAULT 'TD01',
  data_emissione        DATE         NOT NULL,
  giorni_pagamento      SMALLINT UNSIGNED NOT NULL DEFAULT 30,
  data_scadenza         DATE         GENERATED ALWAYS AS
                          (DATE_ADD(data_emissione, INTERVAL giorni_pagamento DAY)) STORED,
  modalita_pagamento    CHAR(4)      NOT NULL,
  natura_iva            VARCHAR(6)   DEFAULT NULL,       -- solo se aliquota 0%
  iban                  VARCHAR(34)  DEFAULT NULL,
  note_causale          TEXT         DEFAULT NULL,
  bollo_virtuale        DECIMAL(5,2) NOT NULL DEFAULT 0,
  PRIMARY KEY (id),
  UNIQUE KEY uq_fattura_numero (azienda_id, anno, progressivo),
  KEY idx_fattura_cliente (cliente_id),
  KEY idx_fattura_data (data_emissione),
  CONSTRAINT fk_fattura_azienda FOREIGN KEY (azienda_id) REFERENCES azienda (id),
  CONSTRAINT fk_fattura_cliente FOREIGN KEY (cliente_id) REFERENCES cliente (id),
  CONSTRAINT fk_fattura_tipo    FOREIGN KEY (tipo_documento) REFERENCES tipo_documento_sdi (codice),
  CONSTRAINT fk_fattura_pag     FOREIGN KEY (modalita_pagamento) REFERENCES modalita_pagamento (codice),
  CONSTRAINT fk_fattura_natura  FOREIGN KEY (natura_iva) REFERENCES natura_iva (codice),
  CONSTRAINT ck_fattura_bollo   CHECK (bollo_virtuale IN (0, 2.00))
) ENGINE=InnoDB;

CREATE TABLE fattura_riga (
  id                  INT UNSIGNED NOT NULL AUTO_INCREMENT,
  fattura_id          INT UNSIGNED NOT NULL,
  n_riga              SMALLINT UNSIGNED NOT NULL,
  articolo_codice     VARCHAR(20)  DEFAULT NULL,
  descrizione         VARCHAR(255) NOT NULL,
  um                  VARCHAR(5)   DEFAULT NULL,
  quantita            DECIMAL(12,3) NOT NULL,
  prezzo_unitario     DECIMAL(12,4) NOT NULL,
  sconto_percentuale  DECIMAL(5,2) NOT NULL DEFAULT 0,
  aliquota_iva        DECIMAL(5,2) NOT NULL,
  imponibile          DECIMAL(14,2) GENERATED ALWAYS AS
                        (ROUND(quantita * prezzo_unitario * (1 - sconto_percentuale / 100), 2)) STORED,
  importo_iva         DECIMAL(14,2) GENERATED ALWAYS AS
                        (ROUND(ROUND(quantita * prezzo_unitario * (1 - sconto_percentuale / 100), 2)
                               * aliquota_iva / 100, 2)) STORED,
  PRIMARY KEY (id),
  UNIQUE KEY uq_fattura_riga (fattura_id, n_riga),
  CONSTRAINT fk_frriga_fattura  FOREIGN KEY (fattura_id) REFERENCES fattura (id) ON DELETE CASCADE,
  CONSTRAINT fk_frriga_articolo FOREIGN KEY (articolo_codice) REFERENCES articolo (codice),
  CONSTRAINT fk_frriga_um       FOREIGN KEY (um) REFERENCES unita_misura (codice),
  CONSTRAINT fk_frriga_iva      FOREIGN KEY (aliquota_iva) REFERENCES aliquota_iva (aliquota),
  CONSTRAINT ck_frriga_qta      CHECK (quantita > 0),
  CONSTRAINT ck_frriga_sconto   CHECK (sconto_percentuale BETWEEN 0 AND 100)
) ENGINE=InnoDB;

-- =====================================================================
-- 4. DOCUMENTI DI TRASPORTO  (fogli "Bolla di accompagnamento" e "DDT")
--    Stessa struttura: li distingue la colonna "tipo".
-- =====================================================================

CREATE TABLE documento_trasporto (
  id                    INT UNSIGNED NOT NULL AUTO_INCREMENT,
  tipo                  ENUM('DDT','BOLLA') NOT NULL,
  azienda_id            INT UNSIGNED NOT NULL,           -- mittente
  cliente_id            INT UNSIGNED NOT NULL,           -- destinatario
  anno                  SMALLINT UNSIGNED NOT NULL,
  progressivo           INT UNSIGNED NOT NULL,
  numero                VARCHAR(20)  GENERATED ALWAYS AS
                          (CONCAT(IF(tipo = 'DDT', 'DDT ', 'BA '),
                                  LPAD(progressivo, 3, '0'), '/', anno)) STORED,
  data_documento        DATE         NOT NULL,
  luogo_destinazione    VARCHAR(250) DEFAULT NULL,       -- se NULL: sede/consegna del cliente
  causale_id            TINYINT UNSIGNED NOT NULL,
  trasporto_a_cura_id   TINYINT UNSIGNED NOT NULL,
  porto_id              TINYINT UNSIGNED DEFAULT NULL,
  inizio_trasporto      DATETIME     DEFAULT NULL,
  aspetto_esteriore     VARCHAR(100) DEFAULT NULL,
  numero_colli          SMALLINT UNSIGNED DEFAULT NULL,
  peso_lordo_kg         DECIMAL(10,2) DEFAULT NULL,
  vettore               VARCHAR(250) DEFAULT NULL,
  fattura_id            INT UNSIGNED DEFAULT NULL,       -- "Rif. fattura"
  annotazioni           TEXT         DEFAULT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_dt_numero (azienda_id, tipo, anno, progressivo),
  KEY idx_dt_cliente (cliente_id),
  KEY idx_dt_fattura (fattura_id),
  CONSTRAINT fk_dt_azienda  FOREIGN KEY (azienda_id) REFERENCES azienda (id),
  CONSTRAINT fk_dt_cliente  FOREIGN KEY (cliente_id) REFERENCES cliente (id),
  CONSTRAINT fk_dt_causale  FOREIGN KEY (causale_id) REFERENCES causale_trasporto (id),
  CONSTRAINT fk_dt_cura     FOREIGN KEY (trasporto_a_cura_id) REFERENCES trasporto_a_cura (id),
  CONSTRAINT fk_dt_porto    FOREIGN KEY (porto_id) REFERENCES porto (id),
  CONSTRAINT fk_dt_fattura  FOREIGN KEY (fattura_id) REFERENCES fattura (id) ON DELETE SET NULL,
  CONSTRAINT ck_dt_colli    CHECK (numero_colli IS NULL OR numero_colli >= 0),
  CONSTRAINT ck_dt_peso     CHECK (peso_lordo_kg IS NULL OR peso_lordo_kg >= 0)
) ENGINE=InnoDB;

CREATE TABLE documento_trasporto_riga (
  id                  INT UNSIGNED NOT NULL AUTO_INCREMENT,
  documento_id        INT UNSIGNED NOT NULL,
  n_riga              SMALLINT UNSIGNED NOT NULL,
  articolo_codice     VARCHAR(20)  DEFAULT NULL,
  descrizione         VARCHAR(255) NOT NULL,
  um                  VARCHAR(5)   DEFAULT NULL,
  quantita            DECIMAL(12,3) NOT NULL,
  note_lotto          VARCHAR(100) DEFAULT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_dtriga (documento_id, n_riga),
  CONSTRAINT fk_dtriga_doc      FOREIGN KEY (documento_id) REFERENCES documento_trasporto (id) ON DELETE CASCADE,
  CONSTRAINT fk_dtriga_articolo FOREIGN KEY (articolo_codice) REFERENCES articolo (codice),
  CONSTRAINT fk_dtriga_um       FOREIGN KEY (um) REFERENCES unita_misura (codice),
  CONSTRAINT ck_dtriga_qta      CHECK (quantita > 0)
) ENGINE=InnoDB;

SET FOREIGN_KEY_CHECKS = 1;

-- =====================================================================
-- 5. DATI: TABELLE DI DECODIFICA (foglio "Liste")
-- =====================================================================

INSERT INTO unita_misura (codice, descrizione) VALUES
 ('pz','Pezzi'),('kg','Chilogrammi'),('g','Grammi'),('m','Metri'),
 ('mq','Metri quadrati'),('mc','Metri cubi'),('l','Litri'),('h','Ore'),
 ('gg','Giorni'),('cf','Confezioni'),('nr','Numero');

INSERT INTO tipo_documento_sdi (codice, descrizione) VALUES
 ('TD01','TD01 - Fattura'),
 ('TD02','TD02 - Acconto/anticipo su fattura'),
 ('TD04','TD04 - Nota di credito'),
 ('TD05','TD05 - Nota di debito'),
 ('TD24','TD24 - Fattura differita (da DDT)');

INSERT INTO aliquota_iva (aliquota, descrizione) VALUES
 (22.00,'IVA ordinaria 22%'),(10.00,'IVA ridotta 10%'),
 (5.00,'IVA ridotta 5%'),(4.00,'IVA minima 4%'),(0.00,'IVA 0% (usare natura)');

INSERT INTO modalita_pagamento (codice, descrizione) VALUES
 ('MP01','MP01 - Contanti'),('MP05','MP05 - Bonifico'),
 ('MP08','MP08 - Carta di pagamento'),('MP12','MP12 - RIBA');

INSERT INTO causale_trasporto (descrizione) VALUES
 ('Vendita'),('Conto lavorazione'),('Reso'),('Conto visione'),
 ('Omaggio'),('Trasferimento tra sedi'),('Riparazione');

INSERT INTO trasporto_a_cura (descrizione) VALUES
 ('Mittente'),('Destinatario'),('Vettore');

INSERT INTO porto (descrizione) VALUES ('Franco'),('Assegnato');

INSERT INTO regime_fiscale (codice, descrizione) VALUES
 ('RF01','RF01 - Ordinario'),('RF19','RF19 - Forfettario'),
 ('RF02','RF02 - Contribuenti minimi');

INSERT INTO natura_iva (codice, descrizione) VALUES
 ('N1','N1 - Escluse art.15'),
 ('N2.1','N2.1 - Non soggette art.7'),
 ('N2.2','N2.2 - Non soggette altri casi'),
 ('N3.1','N3.1 - Non imponibili esportazioni'),
 ('N3.5','N3.5 - Non imponibili dichiarazione d''intento'),
 ('N4','N4 - Esenti'),
 ('N6.3','N6.3 - Inversione contabile subappalto edile'),
 ('N7','N7 - IVA assolta in altro stato UE');

-- =====================================================================
-- 6. DATI: ANAGRAFICHE E DOCUMENTI DI ESEMPIO (dal file Excel)
-- =====================================================================

INSERT INTO azienda
 (id, ragione_sociale, partita_iva, codice_fiscale, indirizzo, cap, citta, provincia,
  regime_fiscale, iban, telefono, email_pec)
VALUES
 (1,'La Tua Azienda S.r.l.','11223344556','11223344556','Via Esempio 1','20100','Milano','MI',
  'RF01','IT60X0542811101000000123456','02 1112223','info@latuazienda.it');

INSERT INTO cliente
 (id, ragione_sociale, partita_iva, codice_fiscale, indirizzo, cap, citta, provincia,
  codice_sdi, pec, email, telefono, indirizzo_consegna)
VALUES
 (1,'Rossi Costruzioni S.r.l.','01234567890','01234567890','Via Garibaldi 12','20121','Milano','MI',
  'ABC1234','rossicostruzioni@pec.it','amministrazione@rossicostruzioni.it','02 1234567',NULL),
 (2,'Bianchi Giuseppe','09876543210','BNCGPP80A01F205X','Via Roma 5','25121','Brescia','BS',
  '0000000',NULL,'g.bianchi@example.it','030 7654321','Via dei Mille 3, 25122 Brescia (BS)');

-- Il prezzo di ART-002 non compare nel file: valore di esempio.
INSERT INTO articolo (codice, descrizione, tipo, um, prezzo_unitario, aliquota_iva) VALUES
 ('ART-001','Sacchi di cemento 25 kg','BENE','pz',8.50,22.00),
 ('ART-002','Calce idrata 20 kg','BENE','pz',6.00,22.00),
 ('SRV-010','Consulenza tecnica in cantiere','SERVIZIO','h',60.00,22.00);

-- Fattura 2026/001 del 10/10/2026, scadenza 30 gg
INSERT INTO fattura
 (id, azienda_id, cliente_id, anno, progressivo, tipo_documento, data_emissione,
  giorni_pagamento, modalita_pagamento, natura_iva, iban, note_causale, bollo_virtuale)
VALUES
 (1,1,2,2026,1,'TD01','2026-10-10',30,'MP05',NULL,'IT60X0542811101000000123456',NULL,0);

INSERT INTO fattura_riga
 (fattura_id, n_riga, articolo_codice, descrizione, um, quantita, prezzo_unitario,
  sconto_percentuale, aliquota_iva)
VALUES
 (1,1,'ART-001','Fornitura sacchi di cemento 25 kg','pz',20,8.50,0,22.00),
 (1,2,'SRV-010','Consulenza tecnica in cantiere','h',3,60.00,10,22.00);

-- DDT 001/2026 e Bolla BA 001/2026 (stessi dati di trasporto)
INSERT INTO documento_trasporto
 (id, tipo, azienda_id, cliente_id, anno, progressivo, data_documento, luogo_destinazione,
  causale_id, trasporto_a_cura_id, porto_id, inizio_trasporto, aspetto_esteriore,
  numero_colli, peso_lordo_kg, vettore, fattura_id)
VALUES
 (1,'DDT',1,2,2026,1,'2026-10-10','Via dei Mille 3, 25122 Brescia (BS)',
  (SELECT id FROM causale_trasporto WHERE descrizione='Vendita'),
  (SELECT id FROM trasporto_a_cura WHERE descrizione='Mittente'),
  (SELECT id FROM porto WHERE descrizione='Franco'),
  '2026-10-10 15:00:00','Scatole di cartone',2,520,
  'Corriere Veloce S.r.l. - Via dei Trasporti 8, Milano',1),
 (2,'BOLLA',1,2,2026,1,'2026-10-10','Via dei Mille 3, 25122 Brescia (BS)',
  (SELECT id FROM causale_trasporto WHERE descrizione='Vendita'),
  (SELECT id FROM trasporto_a_cura WHERE descrizione='Mittente'),
  (SELECT id FROM porto WHERE descrizione='Franco'),
  '2026-10-10 15:00:00','Scatole di cartone',2,520,
  'Corriere Veloce S.r.l. - Via dei Trasporti 8, Milano',1);

INSERT INTO documento_trasporto_riga
 (documento_id, n_riga, articolo_codice, descrizione, um, quantita, note_lotto)
VALUES
 (1,1,'ART-001','Sacchi di cemento 25 kg','pz',20,'Pallet 1'),
 (1,2,'ART-002','Calce idrata 20 kg','pz',10,'Pallet 2'),
 (2,1,'ART-001','Sacchi di cemento 25 kg','pz',20,'Pallet 1'),
 (2,2,'ART-002','Calce idrata 20 kg','pz',10,'Pallet 2');

-- =====================================================================
-- 7. VISTE (replicano i calcoli e le ricerche CERCA.VERT del file Excel)
-- =====================================================================

-- Scheda destinatario (foglio "Destinatari"): ricerca per ragione sociale
CREATE OR REPLACE VIEW v_destinatario AS
SELECT c.id, c.ragione_sociale, c.partita_iva, c.codice_fiscale, c.indirizzo, c.cap,
       c.citta, c.provincia, c.codice_sdi, c.pec, c.email, c.telefono,
       COALESCE(c.indirizzo_consegna,
                CONCAT(c.indirizzo, ', ', c.cap, ' ', c.citta, ' (', c.provincia, ')'))
         AS luogo_consegna_merce
FROM cliente c;

-- Riepilogo IVA per aliquota (blocco "RIEPILOGO IVA E TOTALI")
CREATE OR REPLACE VIEW v_fattura_riepilogo_iva AS
SELECT fattura_id, aliquota_iva,
       SUM(imponibile)  AS imponibile,
       SUM(importo_iva) AS imposta
FROM fattura_riga
GROUP BY fattura_id, aliquota_iva;

-- Testata + totali + riferimento DDT
CREATE OR REPLACE VIEW v_fattura_totali AS
SELECT f.id AS fattura_id, f.numero, f.data_emissione, f.data_scadenza,
       f.tipo_documento, f.modalita_pagamento,
       a.ragione_sociale AS cedente, c.ragione_sociale AS cessionario,
       COALESCE(SUM(r.imponibile), 0)  AS totale_imponibile,
       COALESCE(SUM(r.importo_iva), 0) AS totale_iva,
       f.bollo_virtuale,
       COALESCE(SUM(r.imponibile), 0) + COALESCE(SUM(r.importo_iva), 0) + f.bollo_virtuale
         AS totale_documento,
       (SELECT GROUP_CONCAT(d.numero, ' del ', DATE_FORMAT(d.data_documento, '%d/%m/%Y')
                            SEPARATOR ', ')
          FROM documento_trasporto d
         WHERE d.fattura_id = f.id AND d.tipo = 'DDT') AS riferimento_ddt
FROM fattura f
JOIN azienda a ON a.id = f.azienda_id
JOIN cliente c ON c.id = f.cliente_id
LEFT JOIN fattura_riga r ON r.fattura_id = f.id
GROUP BY f.id, f.numero, f.data_emissione, f.data_scadenza, f.tipo_documento,
         f.modalita_pagamento, a.ragione_sociale, c.ragione_sociale, f.bollo_virtuale;

-- Testata di Bolla / DDT con tutte le decodifiche
CREATE OR REPLACE VIEW v_documento_trasporto AS
SELECT d.id, d.tipo, d.numero, d.data_documento,
       a.ragione_sociale AS mittente, c.ragione_sociale AS destinatario,
       COALESCE(d.luogo_destinazione, v.luogo_consegna_merce) AS luogo_destinazione,
       ca.descrizione AS causale, tc.descrizione AS trasporto_a_cura, p.descrizione AS porto,
       d.inizio_trasporto, d.aspetto_esteriore, d.numero_colli, d.peso_lordo_kg,
       d.vettore, f.numero AS rif_fattura
FROM documento_trasporto d
JOIN azienda a           ON a.id  = d.azienda_id
JOIN cliente c           ON c.id  = d.cliente_id
JOIN v_destinatario v    ON v.id  = c.id
JOIN causale_trasporto ca ON ca.id = d.causale_id
JOIN trasporto_a_cura tc ON tc.id = d.trasporto_a_cura_id
LEFT JOIN porto p        ON p.id  = d.porto_id
LEFT JOIN fattura f      ON f.id  = d.fattura_id;

-- =====================================================================
-- FINE DUMP
-- =====================================================================
