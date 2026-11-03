/* =====================================================================================
Big Pickle + opencode
atue como arquiteto em base de dados
gere um script de criacao das tabelas necessarias para um projeto de delivery de comida. 
tome como modelo o ifood, mas para somente uma loja
use sqlite
guarde o resultado emum arquivo .sql em C:\Projects\Delivery

   PROJETO ..........: Delivery de comida (modelo inspirado no iFood, LOJA UNICA)
   SGBD .............: SQLite 3.35+ (testado em 3.53)
   ARQUIVO ..........: C:\Projects\Delivery\delivery_sqlite.sql
   OBJETIVO .........: Criacao completa do schema: tabelas, constraints, indices,
                       triggers de integridade, views e carga inicial.

   COMO EXECUTAR
   1) Pelo CLI do SQLite:
        sqlite3 C:\Projects\Delivery\sqlite\delivery.db < C:\Projects\Delivery\sqlite\delivery_sqlite.sql

   2) Pelo DB Browser for SQLite:
        Abra/crie o banco e execute este arquivo em "Execute SQL".

   3) Pelo Python:
        import sqlite3
        con = sqlite3.connect(r"C:\Projects\Delivery\delivery.db")
        con.executescript(open(r"C:\Projects\Delivery\delivery_sqlite.sql", encoding="utf-8").read())
        con.close()

   NOTAS DE ARQUITETURA
   - Loja unica: a tabela STORE e um singleton (id = 1). As demais tabelas pertencem
     implicitamente a essa loja; por isso nao ha store_id repetido em todas elas.
   - Valores monetarios em CENTAVOS (INTEGER). Nunca use REAL/FLOAT para dinheiro.
   - Datas/horas em TEXT no padrao ISO-8601 UTC: 'YYYY-MM-DDTHH:MM:SS.SSSZ'.
     Horarios de funcionamento usam TEXT 'HH:MM' (hora local da loja).
   - Booleanos em INTEGER 0/1.
   - Pedidos guardam SNAPSHOT de endereco, nome e preco dos itens. Alteracoes futuras
     no cardapio ou no cadastro do cliente nao reescrevem o historico financeiro.
   - Totais do pedido sao colunas GERADAS (GENERATED) a partir dos itens + frete - desconto.
     O aplicativo NAO deve informar total_cents nem line_total_cents em INSERT/UPDATE.
   - Ao remover itens de um pedido que possui desconto, ajuste/remova o desconto antes.
     O CHECK de total impede que o pedido fique com total negativo.
   - Pagamentos: guarde apenas bandeira e 4 ultimos digitos do cartao. Nunca PAN/CVV.
   - Exclusao fisica de cliente/loja com pedidos e bloqueada por FK. Use is_active = 0.
   - O SQLite exige PRAGMA foreign_keys = ON em CADA conexao. O script habilita, mas o
     aplicativo precisa repetir o PRAGMA ao abrir a conexao.
   - Recomenda-se WAL para concorrencia entre leitura e escrita.

   CONVENCOES DE NOMES
   - Tabelas e colunas em snake_case, no singular.
   - Prefixos: pk_ (primary key), uq_ (unique), ck_ (check), fk_ (foreign key),
     idx_ (indice), trg_ (trigger), vw_ (view).
   ===================================================================================== */

PRAGMA foreign_keys = ON;
PRAGMA journal_mode = WAL;
PRAGMA synchronous = NORMAL;
PRAGMA busy_timeout = 5000;

BEGIN TRANSACTION;

/* =====================================================================================
   1. TABELAS DE DOMINIO (LOOKUPS)
   ===================================================================================== */

CREATE TABLE cuisine_type (
    id         INTEGER PRIMARY KEY,
    name       TEXT NOT NULL UNIQUE,
    is_active  INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0, 1))
);

CREATE TABLE order_status (
    id          INTEGER PRIMARY KEY,
    code        TEXT NOT NULL UNIQUE,
    name        TEXT NOT NULL,
    sort_order  INTEGER NOT NULL DEFAULT 0,
    is_final    INTEGER NOT NULL DEFAULT 0 CHECK (is_final IN (0, 1))
);

CREATE TABLE payment_method_type (
    id         INTEGER PRIMARY KEY,
    code       TEXT NOT NULL UNIQUE,
    name       TEXT NOT NULL,
    is_online  INTEGER NOT NULL DEFAULT 1 CHECK (is_online IN (0, 1)),
    is_active  INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0, 1))
);

CREATE TABLE payment_status (
    id        INTEGER PRIMARY KEY,
    code      TEXT NOT NULL UNIQUE,
    name      TEXT NOT NULL,
    is_final  INTEGER NOT NULL DEFAULT 0 CHECK (is_final IN (0, 1))
);

CREATE TABLE order_channel (
    id    INTEGER PRIMARY KEY,
    code  TEXT NOT NULL UNIQUE,
    name  TEXT NOT NULL
);

CREATE TABLE cancellation_reason (
    id           INTEGER PRIMARY KEY,
    code         TEXT NOT NULL UNIQUE,
    name         TEXT NOT NULL,
    responsible  TEXT NOT NULL CHECK (responsible IN ('CUSTOMER', 'STORE', 'COURIER', 'SYSTEM')),
    is_active    INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0, 1))
);

CREATE TABLE vehicle_type (
    id    INTEGER PRIMARY KEY,
    code  TEXT NOT NULL UNIQUE,
    name  TEXT NOT NULL
);

/* =====================================================================================
   2. LOJA (SINGLETON) / HORARIOS / AREAS DE ENTREGA / EQUIPE
   ===================================================================================== */

CREATE TABLE store (
    id                        INTEGER PRIMARY KEY CHECK (id = 1),
    legal_name                TEXT NOT NULL,
    trade_name                TEXT NOT NULL,
    document                  TEXT NOT NULL UNIQUE,          -- CNPJ, somente digitos
    email                     TEXT NOT NULL,
    phone                     TEXT,
    cuisine_type_id           INTEGER REFERENCES cuisine_type(id) ON DELETE SET NULL,
    description               TEXT,
    logo_url                  TEXT,
    cover_url                 TEXT,
    street                    TEXT NOT NULL,
    number                    TEXT,
    complement                TEXT,
    district                  TEXT NOT NULL,
    city                      TEXT NOT NULL,
    state                     TEXT NOT NULL CHECK (length(state) = 2 AND state = upper(state)),
    zip_code                  TEXT NOT NULL,
    country                   TEXT NOT NULL DEFAULT 'Brasil',
    latitude                  REAL CHECK (latitude IS NULL OR latitude BETWEEN -90 AND 90),
    longitude                 REAL CHECK (longitude IS NULL OR longitude BETWEEN -180 AND 180),
    delivery_fee_base_cents   INTEGER NOT NULL DEFAULT 0 CHECK (delivery_fee_base_cents >= 0),
    min_order_value_cents     INTEGER NOT NULL DEFAULT 0 CHECK (min_order_value_cents >= 0),
    average_prep_minutes      INTEGER NOT NULL DEFAULT 30 CHECK (average_prep_minutes >= 0),
    average_delivery_minutes  INTEGER NOT NULL DEFAULT 30 CHECK (average_delivery_minutes >= 0),
    is_open_manual            INTEGER NOT NULL DEFAULT 1 CHECK (is_open_manual IN (0, 1)),
    is_active                 INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0, 1)),
    rating_avg                REAL NOT NULL DEFAULT 0 CHECK (rating_avg BETWEEN 0 AND 5),
    rating_count              INTEGER NOT NULL DEFAULT 0 CHECK (rating_count >= 0),
    created_at                TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
    updated_at                TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);

CREATE TABLE store_opening_hours (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    day_of_week  INTEGER NOT NULL CHECK (day_of_week BETWEEN 0 AND 6),  -- 0 = domingo ... 6 = sabado
    open_time    TEXT NOT NULL,
    close_time   TEXT NOT NULL,   -- close_time < open_time indica turno que vira a madrugada
    is_active    INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0, 1)),
    CHECK (length(open_time) = 5 AND open_time GLOB '[0-2][0-9]:[0-5][0-9]' AND open_time BETWEEN '00:00' AND '23:59'),
    CHECK (length(close_time) = 5 AND close_time GLOB '[0-2][0-9]:[0-5][0-9]' AND close_time BETWEEN '00:00' AND '23:59'),
    CHECK (open_time <> close_time),
    UNIQUE (day_of_week, open_time)
);

CREATE TABLE delivery_zone (
    id                       INTEGER PRIMARY KEY AUTOINCREMENT,
    city                     TEXT NOT NULL,
    district                 TEXT,
    zip_code_prefix          TEXT,
    delivery_fee_cents       INTEGER NOT NULL DEFAULT 0 CHECK (delivery_fee_cents >= 0),
    min_order_value_cents    INTEGER NOT NULL DEFAULT 0 CHECK (min_order_value_cents >= 0),
    estimated_minutes        INTEGER NOT NULL DEFAULT 30 CHECK (estimated_minutes >= 0),
    is_active                INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0, 1)),
    created_at               TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
    updated_at               TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
    CHECK (district IS NOT NULL OR zip_code_prefix IS NOT NULL)
);

CREATE TABLE store_payment_method (
    id                      INTEGER PRIMARY KEY AUTOINCREMENT,
    payment_method_type_id  INTEGER NOT NULL REFERENCES payment_method_type(id) ON DELETE RESTRICT,
    is_active               INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0, 1)),
    UNIQUE (payment_method_type_id)
);

CREATE TABLE store_user (
    id             INTEGER PRIMARY KEY AUTOINCREMENT,
    full_name      TEXT NOT NULL,
    email          TEXT NOT NULL COLLATE NOCASE UNIQUE,
    password_hash  TEXT NOT NULL,
    role           TEXT NOT NULL DEFAULT 'OPERATOR' CHECK (role IN ('OWNER', 'MANAGER', 'OPERATOR', 'KITCHEN')),
    is_active      INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0, 1)),
    last_login_at  TEXT,
    created_at     TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
    updated_at     TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);

/* =====================================================================================
   3. CLIENTES
   ===================================================================================== */

CREATE TABLE customer (
    id                INTEGER PRIMARY KEY AUTOINCREMENT,
    full_name         TEXT NOT NULL,
    email             TEXT COLLATE NOCASE UNIQUE,
    phone             TEXT NOT NULL UNIQUE,
    document          TEXT UNIQUE,                -- CPF, somente digitos
    password_hash     TEXT,
    birth_date        TEXT,
    marketing_opt_in  INTEGER NOT NULL DEFAULT 0 CHECK (marketing_opt_in IN (0, 1)),
    is_active         INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0, 1)),
    last_login_at     TEXT,
    created_at        TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
    updated_at        TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);

CREATE TABLE customer_address (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    customer_id  INTEGER NOT NULL REFERENCES customer(id) ON DELETE CASCADE,
    label        TEXT NOT NULL DEFAULT 'Casa',
    street       TEXT NOT NULL,
    number       TEXT,
    complement   TEXT,
    district     TEXT NOT NULL,
    city         TEXT NOT NULL,
    state        TEXT NOT NULL CHECK (length(state) = 2 AND state = upper(state)),
    zip_code     TEXT NOT NULL,
    country      TEXT NOT NULL DEFAULT 'Brasil',
    latitude     REAL CHECK (latitude IS NULL OR latitude BETWEEN -90 AND 90),
    longitude    REAL CHECK (longitude IS NULL OR longitude BETWEEN -180 AND 180),
    is_default   INTEGER NOT NULL DEFAULT 0 CHECK (is_default IN (0, 1)),
    is_active    INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0, 1)),
    created_at   TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
    updated_at   TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);

/* =====================================================================================
   4. ENTREGADORES
   ===================================================================================== */

CREATE TABLE courier (
    id                INTEGER PRIMARY KEY AUTOINCREMENT,
    full_name         TEXT NOT NULL,
    email             TEXT COLLATE NOCASE UNIQUE,
    phone             TEXT NOT NULL UNIQUE,
    document          TEXT UNIQUE,                -- CPF, somente digitos
    vehicle_type_id   INTEGER NOT NULL REFERENCES vehicle_type(id) ON DELETE RESTRICT,
    vehicle_plate     TEXT,
    is_active         INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0, 1)),
    rating_avg        REAL NOT NULL DEFAULT 5 CHECK (rating_avg BETWEEN 0 AND 5),
    total_deliveries  INTEGER NOT NULL DEFAULT 0 CHECK (total_deliveries >= 0),
    created_at        TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
    updated_at        TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);

/* =====================================================================================
   5. CARDAPIO
   ===================================================================================== */

CREATE TABLE menu_category (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    name         TEXT NOT NULL UNIQUE,
    description  TEXT,
    sort_order   INTEGER NOT NULL DEFAULT 0,
    is_active    INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0, 1)),
    created_at   TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
    updated_at   TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);

CREATE TABLE menu_item (
    id                      INTEGER PRIMARY KEY AUTOINCREMENT,
    menu_category_id        INTEGER NOT NULL REFERENCES menu_category(id) ON DELETE RESTRICT,
    name                    TEXT NOT NULL,
    description             TEXT,
    price_cents             INTEGER NOT NULL CHECK (price_cents > 0),
    promotional_price_cents INTEGER CHECK (promotional_price_cents IS NULL OR (promotional_price_cents > 0 AND promotional_price_cents <= price_cents)),
    image_url               TEXT,
    prep_time_minutes       INTEGER CHECK (prep_time_minutes IS NULL OR prep_time_minutes >= 0),
    serves_people           INTEGER CHECK (serves_people IS NULL OR serves_people > 0),
    is_available            INTEGER NOT NULL DEFAULT 1 CHECK (is_available IN (0, 1)),
    is_active               INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0, 1)),
    sort_order              INTEGER NOT NULL DEFAULT 0,
    created_at              TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
    updated_at              TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);

CREATE TABLE menu_item_option_group (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    menu_item_id  INTEGER NOT NULL REFERENCES menu_item(id) ON DELETE CASCADE,
    name          TEXT NOT NULL,
    description   TEXT,
    min_choices   INTEGER NOT NULL DEFAULT 0 CHECK (min_choices >= 0),
    max_choices   INTEGER NOT NULL DEFAULT 1 CHECK (max_choices >= 1),
    is_required   INTEGER NOT NULL DEFAULT 0 CHECK (is_required IN (0, 1)),
    sort_order    INTEGER NOT NULL DEFAULT 0,
    is_active     INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0, 1)),
    CHECK (min_choices <= max_choices),
    CHECK (is_required = 0 OR min_choices >= 1),
    UNIQUE (menu_item_id, name)
);

CREATE TABLE menu_item_option (
    id                INTEGER PRIMARY KEY AUTOINCREMENT,
    option_group_id   INTEGER NOT NULL REFERENCES menu_item_option_group(id) ON DELETE CASCADE,
    name              TEXT NOT NULL,
    price_delta_cents INTEGER NOT NULL DEFAULT 0,   -- pode ser negativo (ex.: "sem queijo")
    is_available      INTEGER NOT NULL DEFAULT 1 CHECK (is_available IN (0, 1)),
    sort_order        INTEGER NOT NULL DEFAULT 0,
    UNIQUE (option_group_id, name)
);

/* =====================================================================================
   6. CUPONS / PROMOCOES
   ===================================================================================== */

CREATE TABLE coupon (
    id                   INTEGER PRIMARY KEY AUTOINCREMENT,
    code                 TEXT NOT NULL COLLATE NOCASE UNIQUE,
    description          TEXT,
    discount_type        TEXT NOT NULL CHECK (discount_type IN ('PERCENT', 'FIXED', 'FREE_DELIVERY')),
    discount_value       INTEGER NOT NULL DEFAULT 0 CHECK (discount_value >= 0),
    min_order_value_cents INTEGER NOT NULL DEFAULT 0 CHECK (min_order_value_cents >= 0),
    max_discount_cents   INTEGER CHECK (max_discount_cents IS NULL OR max_discount_cents >= 0),
    starts_at            TEXT,
    ends_at              TEXT,
    total_usage_limit    INTEGER CHECK (total_usage_limit IS NULL OR total_usage_limit >= 1),
    per_customer_limit   INTEGER NOT NULL DEFAULT 1 CHECK (per_customer_limit >= 1),
    times_used           INTEGER NOT NULL DEFAULT 0 CHECK (times_used >= 0),
    is_active            INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0, 1)),
    created_at           TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
    updated_at           TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
    -- PERCENT: discount_value de 0 a 100. FIXED: valor em centavos. FREE_DELIVERY: 0.
    CHECK (discount_type <> 'PERCENT' OR discount_value BETWEEN 0 AND 100),
    CHECK (discount_type <> 'FREE_DELIVERY' OR discount_value = 0),
    CHECK (ends_at IS NULL OR starts_at IS NULL OR ends_at > starts_at)
);

/* =====================================================================================
   7. PEDIDOS
   ===================================================================================== */

CREATE TABLE customer_order (
    id                       INTEGER PRIMARY KEY AUTOINCREMENT,
    order_number             TEXT UNIQUE,                 -- gerado pelo trigger (PD + id)
    customer_id              INTEGER NOT NULL REFERENCES customer(id) ON DELETE RESTRICT,
    status_id                INTEGER NOT NULL REFERENCES order_status(id) ON DELETE RESTRICT,
    channel_id               INTEGER NOT NULL REFERENCES order_channel(id) ON DELETE RESTRICT,
    coupon_id                INTEGER REFERENCES coupon(id) ON DELETE SET NULL,
    customer_address_id      INTEGER REFERENCES customer_address(id) ON DELETE SET NULL,
    delivery_type            TEXT NOT NULL DEFAULT 'DELIVERY' CHECK (delivery_type IN ('DELIVERY', 'PICKUP')),

    -- Snapshot do endereco de entrega (imutavel para o pedido)
    delivery_street          TEXT,
    delivery_number          TEXT,
    delivery_complement      TEXT,
    delivery_district        TEXT,
    delivery_city            TEXT,
    delivery_state           TEXT CHECK (delivery_state IS NULL OR (length(delivery_state) = 2 AND delivery_state = upper(delivery_state))),
    delivery_zip_code        TEXT,
    delivery_country         TEXT DEFAULT 'Brasil',
    delivery_latitude        REAL CHECK (delivery_latitude IS NULL OR delivery_latitude BETWEEN -90 AND 90),
    delivery_longitude       REAL CHECK (delivery_longitude IS NULL OR delivery_longitude BETWEEN -180 AND 180),

    items_subtotal_cents     INTEGER NOT NULL DEFAULT 0 CHECK (items_subtotal_cents >= 0),
    delivery_fee_cents       INTEGER NOT NULL DEFAULT 0 CHECK (delivery_fee_cents >= 0),
    discount_total_cents     INTEGER NOT NULL DEFAULT 0 CHECK (discount_total_cents >= 0),
    total_cents              INTEGER GENERATED ALWAYS AS (items_subtotal_cents + delivery_fee_cents - discount_total_cents) STORED,
    change_for_cents         INTEGER CHECK (change_for_cents IS NULL OR change_for_cents >= 0),

    notes                    TEXT,
    status_note              TEXT,
    status_changed_by_type   TEXT NOT NULL DEFAULT 'SYSTEM' CHECK (status_changed_by_type IN ('CUSTOMER', 'STORE', 'COURIER', 'SYSTEM')),
    status_changed_by_id     INTEGER,

    placed_at                TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
    scheduled_for            TEXT,
    estimated_delivery_at    TEXT,
    confirmed_at             TEXT,
    ready_at                 TEXT,
    dispatched_at            TEXT,
    delivered_at             TEXT,
    cancelled_at             TEXT,
    cancellation_reason_id   INTEGER REFERENCES cancellation_reason(id) ON DELETE SET NULL,

    created_at               TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
    updated_at               TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),

    CHECK (items_subtotal_cents + delivery_fee_cents - discount_total_cents >= 0),
    CHECK (delivery_type <> 'DELIVERY' OR delivery_street IS NOT NULL),
    CHECK (delivery_type <> 'PICKUP' OR delivery_fee_cents = 0),
    CHECK (scheduled_for IS NULL OR scheduled_for >= placed_at)
);

CREATE TABLE order_item (
    id                        INTEGER PRIMARY KEY AUTOINCREMENT,
    order_id                  INTEGER NOT NULL REFERENCES customer_order(id) ON DELETE CASCADE,
    menu_item_id              INTEGER REFERENCES menu_item(id) ON DELETE SET NULL,
    item_name                 TEXT NOT NULL,              -- snapshot
    unit_price_cents          INTEGER NOT NULL CHECK (unit_price_cents >= 0), -- snapshot do preco base
    options_unit_total_cents  INTEGER NOT NULL DEFAULT 0, -- soma dos adicionais por unidade
    quantity                  INTEGER NOT NULL DEFAULT 1 CHECK (quantity > 0),
    line_total_cents          INTEGER GENERATED ALWAYS AS ((unit_price_cents + options_unit_total_cents) * quantity) STORED,
    notes                     TEXT,
    created_at                TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
    CHECK (unit_price_cents + options_unit_total_cents >= 0)
);

CREATE TABLE order_item_option (
    id                      INTEGER PRIMARY KEY AUTOINCREMENT,
    order_item_id           INTEGER NOT NULL REFERENCES order_item(id) ON DELETE CASCADE,
    menu_item_option_id     INTEGER REFERENCES menu_item_option(id) ON DELETE SET NULL,
    option_group_name       TEXT NOT NULL,                -- snapshot
    option_name             TEXT NOT NULL,                -- snapshot
    unit_price_delta_cents  INTEGER NOT NULL DEFAULT 0,
    quantity                INTEGER NOT NULL DEFAULT 1 CHECK (quantity > 0)
);

CREATE TABLE order_status_history (
    id               INTEGER PRIMARY KEY AUTOINCREMENT,
    order_id         INTEGER NOT NULL REFERENCES customer_order(id) ON DELETE CASCADE,
    status_id        INTEGER NOT NULL REFERENCES order_status(id) ON DELETE RESTRICT,
    changed_at       TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
    changed_by_type  TEXT NOT NULL DEFAULT 'SYSTEM' CHECK (changed_by_type IN ('CUSTOMER', 'STORE', 'COURIER', 'SYSTEM')),
    changed_by_id    INTEGER,
    notes            TEXT
);

CREATE TABLE coupon_redemption (
    id                      INTEGER PRIMARY KEY AUTOINCREMENT,
    coupon_id               INTEGER NOT NULL REFERENCES coupon(id) ON DELETE RESTRICT,
    customer_id             INTEGER NOT NULL REFERENCES customer(id) ON DELETE RESTRICT,
    order_id                INTEGER NOT NULL REFERENCES customer_order(id) ON DELETE CASCADE,
    discount_applied_cents  INTEGER NOT NULL DEFAULT 0 CHECK (discount_applied_cents >= 0),
    redeemed_at             TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
    UNIQUE (order_id)
);

/* =====================================================================================
   8. PAGAMENTOS
   ===================================================================================== */

CREATE TABLE payment (
    id                      INTEGER PRIMARY KEY AUTOINCREMENT,
    order_id                INTEGER NOT NULL REFERENCES customer_order(id) ON DELETE CASCADE,
    payment_method_type_id  INTEGER NOT NULL REFERENCES payment_method_type(id) ON DELETE RESTRICT,
    status_id               INTEGER NOT NULL REFERENCES payment_status(id) ON DELETE RESTRICT,
    amount_cents            INTEGER NOT NULL CHECK (amount_cents >= 0),
    installments            INTEGER NOT NULL DEFAULT 1 CHECK (installments BETWEEN 1 AND 24),
    card_brand              TEXT,
    card_last4              TEXT CHECK (card_last4 IS NULL OR (length(card_last4) = 4 AND card_last4 GLOB '[0-9][0-9][0-9][0-9]')),
    authorization_code      TEXT,
    gateway_transaction_id  TEXT,
    paid_at                 TEXT,
    refunded_at             TEXT,
    created_at              TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
    updated_at              TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);

CREATE TABLE payment_event (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    payment_id  INTEGER NOT NULL REFERENCES payment(id) ON DELETE CASCADE,
    event_type  TEXT NOT NULL,                    -- WEBHOOK, AUTHORIZE, CAPTURE, REFUND...
    payload     TEXT,                             -- JSON do gateway
    created_at  TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);

/* =====================================================================================
   9. ENTREGA / RASTREAMENTO
   ===================================================================================== */

CREATE TABLE courier_delivery (
    id                 INTEGER PRIMARY KEY AUTOINCREMENT,
    order_id           INTEGER NOT NULL REFERENCES customer_order(id) ON DELETE CASCADE,
    courier_id         INTEGER NOT NULL REFERENCES courier(id) ON DELETE RESTRICT,
    status             TEXT NOT NULL DEFAULT 'PENDING' CHECK (status IN ('PENDING', 'ASSIGNED', 'ACCEPTED', 'PICKED_UP', 'DELIVERED', 'CANCELLED')),
    assigned_at        TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
    accepted_at        TEXT,
    picked_up_at       TEXT,
    delivered_at       TEXT,
    distance_km        REAL CHECK (distance_km IS NULL OR distance_km >= 0),
    courier_fee_cents  INTEGER NOT NULL DEFAULT 0 CHECK (courier_fee_cents >= 0),
    current_latitude   REAL CHECK (current_latitude IS NULL OR current_latitude BETWEEN -90 AND 90),
    current_longitude  REAL CHECK (current_longitude IS NULL OR current_longitude BETWEEN -180 AND 180),
    created_at         TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
    updated_at         TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
    UNIQUE (order_id)
);

CREATE TABLE delivery_tracking (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    delivery_id  INTEGER NOT NULL REFERENCES courier_delivery(id) ON DELETE CASCADE,
    latitude     REAL NOT NULL CHECK (latitude BETWEEN -90 AND 90),
    longitude    REAL NOT NULL CHECK (longitude BETWEEN -180 AND 180),
    recorded_at  TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);

/* =====================================================================================
   10. AVALIACOES E MENSAGENS DO PEDIDO
   ===================================================================================== */

CREATE TABLE order_review (
    id               INTEGER PRIMARY KEY AUTOINCREMENT,
    order_id         INTEGER NOT NULL REFERENCES customer_order(id) ON DELETE CASCADE,
    customer_id      INTEGER NOT NULL REFERENCES customer(id) ON DELETE RESTRICT,
    courier_id       INTEGER REFERENCES courier(id) ON DELETE SET NULL,
    store_rating     INTEGER NOT NULL CHECK (store_rating BETWEEN 1 AND 5),
    courier_rating   INTEGER CHECK (courier_rating IS NULL OR courier_rating BETWEEN 1 AND 5),
    delivery_rating  INTEGER CHECK (delivery_rating IS NULL OR delivery_rating BETWEEN 1 AND 5),
    review_comment   TEXT,
    store_reply      TEXT,
    replied_at       TEXT,
    created_at       TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
    updated_at       TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
    UNIQUE (order_id)
);

CREATE TABLE order_message (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    order_id     INTEGER NOT NULL REFERENCES customer_order(id) ON DELETE CASCADE,
    sender_type  TEXT NOT NULL CHECK (sender_type IN ('CUSTOMER', 'STORE', 'COURIER', 'SYSTEM')),
    sender_id    INTEGER,
    message      TEXT NOT NULL CHECK (length(trim(message)) > 0),
    sent_at      TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
    read_at      TEXT
);

/* =====================================================================================
   11. AUDITORIA
   ===================================================================================== */

CREATE TABLE audit_log (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    table_name  TEXT NOT NULL,
    record_id   TEXT NOT NULL,
    operation   TEXT NOT NULL CHECK (operation IN ('I', 'U', 'D')),
    changed_by  TEXT,
    changed_at  TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
    old_values  TEXT,
    new_values  TEXT
);

/* =====================================================================================
   12. INDICES
   O SQLite nao cria indice automatico para foreign keys; todos os acessos por FK
   relevantes estao indexados abaixo.
   ===================================================================================== */

CREATE INDEX idx_customer_address_customer ON customer_address (customer_id);
CREATE INDEX idx_customer_address_city     ON customer_address (city, district);
CREATE UNIQUE INDEX ux_customer_address_default
    ON customer_address (customer_id)
    WHERE is_default = 1;

CREATE INDEX idx_store_opening_hours_dow   ON store_opening_hours (day_of_week);
CREATE INDEX idx_delivery_zone_city        ON delivery_zone (city, district);
CREATE INDEX idx_store_payment_method_type ON store_payment_method (payment_method_type_id);
CREATE INDEX idx_store_user_role           ON store_user (role);

CREATE INDEX idx_menu_category_sort        ON menu_category (sort_order);
CREATE INDEX idx_menu_item_category        ON menu_item (menu_category_id, is_available);
CREATE INDEX idx_menu_item_active          ON menu_item (is_active, is_available);
CREATE INDEX idx_option_group_item         ON menu_item_option_group (menu_item_id);
CREATE INDEX idx_option_group_option       ON menu_item_option (option_group_id);

CREATE INDEX idx_coupon_validity           ON coupon (is_active, starts_at, ends_at);

CREATE INDEX idx_order_customer            ON customer_order (customer_id, placed_at);
CREATE INDEX idx_order_status              ON customer_order (status_id);
CREATE INDEX idx_order_channel             ON customer_order (channel_id);
CREATE INDEX idx_order_coupon              ON customer_order (coupon_id);
CREATE INDEX idx_order_placed_at           ON customer_order (placed_at);
CREATE INDEX idx_order_scheduled           ON customer_order (scheduled_for);
CREATE INDEX idx_order_cancel_reason       ON customer_order (cancellation_reason_id);

CREATE INDEX idx_order_item_order          ON order_item (order_id);
CREATE INDEX idx_order_item_menu           ON order_item (menu_item_id);
CREATE INDEX idx_order_item_option_item    ON order_item_option (order_item_id);
CREATE INDEX idx_order_item_option_menu    ON order_item_option (menu_item_option_id);

CREATE INDEX idx_status_history_order      ON order_status_history (order_id, changed_at);
CREATE INDEX idx_status_history_status     ON order_status_history (status_id);

CREATE INDEX idx_redemption_coupon         ON coupon_redemption (coupon_id);
CREATE INDEX idx_redemption_customer       ON coupon_redemption (customer_id);

CREATE INDEX idx_payment_order             ON payment (order_id);
CREATE INDEX idx_payment_status            ON payment (status_id);
CREATE INDEX idx_payment_method            ON payment (payment_method_type_id);
CREATE INDEX idx_payment_gateway           ON payment (gateway_transaction_id);
CREATE INDEX idx_payment_event_payment     ON payment_event (payment_id);

CREATE INDEX idx_courier_vehicle           ON courier (vehicle_type_id);
CREATE INDEX idx_courier_active            ON courier (is_active);

CREATE INDEX idx_delivery_courier          ON courier_delivery (courier_id, status);
CREATE INDEX idx_delivery_status           ON courier_delivery (status);
CREATE INDEX idx_tracking_delivery         ON delivery_tracking (delivery_id, recorded_at);

CREATE INDEX idx_review_customer           ON order_review (customer_id);
CREATE INDEX idx_review_courier            ON order_review (courier_id);
CREATE INDEX idx_message_order             ON order_message (order_id, sent_at);

CREATE INDEX idx_audit_table_record        ON audit_log (table_name, record_id, changed_at);
CREATE INDEX idx_audit_changed_at          ON audit_log (changed_at);

/* =====================================================================================
   13. TRIGGERS
   ===================================================================================== */

/* ---- 13.1 updated_at automatico -------------------------------------------------- */

CREATE TRIGGER trg_store_updated_at
AFTER UPDATE ON store
FOR EACH ROW
WHEN NEW.updated_at = OLD.updated_at
BEGIN
    UPDATE store SET updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now') WHERE id = NEW.id;
END;

CREATE TRIGGER trg_delivery_zone_updated_at
AFTER UPDATE ON delivery_zone
FOR EACH ROW
WHEN NEW.updated_at = OLD.updated_at
BEGIN
    UPDATE delivery_zone SET updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now') WHERE id = NEW.id;
END;

CREATE TRIGGER trg_store_user_updated_at
AFTER UPDATE ON store_user
FOR EACH ROW
WHEN NEW.updated_at = OLD.updated_at
BEGIN
    UPDATE store_user SET updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now') WHERE id = NEW.id;
END;

CREATE TRIGGER trg_customer_updated_at
AFTER UPDATE ON customer
FOR EACH ROW
WHEN NEW.updated_at = OLD.updated_at
BEGIN
    UPDATE customer SET updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now') WHERE id = NEW.id;
END;

CREATE TRIGGER trg_customer_address_updated_at
AFTER UPDATE ON customer_address
FOR EACH ROW
WHEN NEW.updated_at = OLD.updated_at
BEGIN
    UPDATE customer_address SET updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now') WHERE id = NEW.id;
END;

CREATE TRIGGER trg_courier_updated_at
AFTER UPDATE ON courier
FOR EACH ROW
WHEN NEW.updated_at = OLD.updated_at
BEGIN
    UPDATE courier SET updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now') WHERE id = NEW.id;
END;

CREATE TRIGGER trg_menu_category_updated_at
AFTER UPDATE ON menu_category
FOR EACH ROW
WHEN NEW.updated_at = OLD.updated_at
BEGIN
    UPDATE menu_category SET updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now') WHERE id = NEW.id;
END;

CREATE TRIGGER trg_menu_item_updated_at
AFTER UPDATE ON menu_item
FOR EACH ROW
WHEN NEW.updated_at = OLD.updated_at
BEGIN
    UPDATE menu_item SET updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now') WHERE id = NEW.id;
END;

CREATE TRIGGER trg_coupon_updated_at
AFTER UPDATE ON coupon
FOR EACH ROW
WHEN NEW.updated_at = OLD.updated_at
BEGIN
    UPDATE coupon SET updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now') WHERE id = NEW.id;
END;

CREATE TRIGGER trg_customer_order_updated_at
AFTER UPDATE ON customer_order
FOR EACH ROW
WHEN NEW.updated_at = OLD.updated_at
BEGIN
    UPDATE customer_order SET updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now') WHERE id = NEW.id;
END;

CREATE TRIGGER trg_payment_updated_at
AFTER UPDATE ON payment
FOR EACH ROW
WHEN NEW.updated_at = OLD.updated_at
BEGIN
    UPDATE payment SET updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now') WHERE id = NEW.id;
END;

CREATE TRIGGER trg_courier_delivery_updated_at
AFTER UPDATE ON courier_delivery
FOR EACH ROW
WHEN NEW.updated_at = OLD.updated_at
BEGIN
    UPDATE courier_delivery SET updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now') WHERE id = NEW.id;
END;

CREATE TRIGGER trg_order_review_updated_at
AFTER UPDATE ON order_review
FOR EACH ROW
WHEN NEW.updated_at = OLD.updated_at
BEGIN
    UPDATE order_review SET updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now') WHERE id = NEW.id;
END;

/* ---- 13.2 Endereco padrao do cliente --------------------------------------------- */

CREATE TRIGGER trg_customer_address_default_bi
BEFORE INSERT ON customer_address
FOR EACH ROW
WHEN NEW.is_default = 1
BEGIN
    UPDATE customer_address
       SET is_default = 0
     WHERE customer_id = NEW.customer_id
       AND is_default = 1;
END;

CREATE TRIGGER trg_customer_address_default_bu
BEFORE UPDATE OF is_default ON customer_address
FOR EACH ROW
WHEN NEW.is_default = 1 AND OLD.is_default = 0
BEGIN
    UPDATE customer_address
       SET is_default = 0
     WHERE customer_id = NEW.customer_id
       AND id <> NEW.id
       AND is_default = 1;
END;

/* ---- 13.3 Codigo amigavel e historico de status do pedido ------------------------ */

CREATE TRIGGER trg_customer_order_number
AFTER INSERT ON customer_order
FOR EACH ROW
WHEN NEW.order_number IS NULL
BEGIN
    UPDATE customer_order
       SET order_number = 'PD' || printf('%010d', NEW.id)
     WHERE id = NEW.id;
END;

CREATE TRIGGER trg_customer_order_history_ai
AFTER INSERT ON customer_order
FOR EACH ROW
BEGIN
    INSERT INTO order_status_history (order_id, status_id, changed_by_type, changed_by_id, notes)
    VALUES (NEW.id, NEW.status_id, NEW.status_changed_by_type, NEW.status_changed_by_id, 'Pedido criado');
END;

CREATE TRIGGER trg_customer_order_history_au
AFTER UPDATE OF status_id ON customer_order
FOR EACH ROW
WHEN NEW.status_id <> OLD.status_id
BEGIN
    INSERT INTO order_status_history (order_id, status_id, changed_by_type, changed_by_id, notes)
    VALUES (NEW.id, NEW.status_id, NEW.status_changed_by_type, NEW.status_changed_by_id, NEW.status_note);
END;

/* ---- 13.4 Totais do pedido (itens + frete - desconto) ---------------------------- */

CREATE TRIGGER trg_order_item_totals_ai
AFTER INSERT ON order_item
FOR EACH ROW
BEGIN
    UPDATE customer_order
       SET items_subtotal_cents = (
               SELECT COALESCE(SUM(line_total_cents), 0)
                 FROM order_item
                WHERE order_id = NEW.order_id
           ),
           updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
     WHERE id = NEW.order_id;
END;

CREATE TRIGGER trg_order_item_totals_au
AFTER UPDATE ON order_item
FOR EACH ROW
BEGIN
    UPDATE customer_order
       SET items_subtotal_cents = (
               SELECT COALESCE(SUM(line_total_cents), 0)
                 FROM order_item
                WHERE order_id = NEW.order_id
           ),
           updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
     WHERE id = NEW.order_id;

    UPDATE customer_order
       SET items_subtotal_cents = (
               SELECT COALESCE(SUM(line_total_cents), 0)
                 FROM order_item
                WHERE order_id = OLD.order_id
           ),
           updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
     WHERE id = OLD.order_id
       AND OLD.order_id <> NEW.order_id;
END;

CREATE TRIGGER trg_order_item_totals_ad
AFTER DELETE ON order_item
FOR EACH ROW
BEGIN
    UPDATE customer_order
       SET items_subtotal_cents = (
               SELECT COALESCE(SUM(line_total_cents), 0)
                 FROM order_item
                WHERE order_id = OLD.order_id
           ),
           updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
     WHERE id = OLD.order_id;
END;

/* ---- 13.5 Totais dos adicionais por item ----------------------------------------- */

CREATE TRIGGER trg_order_item_option_totals_ai
AFTER INSERT ON order_item_option
FOR EACH ROW
BEGIN
    UPDATE order_item
       SET options_unit_total_cents = (
               SELECT COALESCE(SUM(unit_price_delta_cents * quantity), 0)
                 FROM order_item_option
                WHERE order_item_id = NEW.order_item_id
           )
     WHERE id = NEW.order_item_id;
END;

CREATE TRIGGER trg_order_item_option_totals_au
AFTER UPDATE ON order_item_option
FOR EACH ROW
BEGIN
    UPDATE order_item
       SET options_unit_total_cents = (
               SELECT COALESCE(SUM(unit_price_delta_cents * quantity), 0)
                 FROM order_item_option
                WHERE order_item_id = NEW.order_item_id
           )
     WHERE id = NEW.order_item_id;

    UPDATE order_item
       SET options_unit_total_cents = (
               SELECT COALESCE(SUM(unit_price_delta_cents * quantity), 0)
                 FROM order_item_option
                WHERE order_item_id = OLD.order_item_id
           )
     WHERE id = OLD.order_item_id
       AND OLD.order_item_id <> NEW.order_item_id;
END;

CREATE TRIGGER trg_order_item_option_totals_ad
AFTER DELETE ON order_item_option
FOR EACH ROW
BEGIN
    UPDATE order_item
       SET options_unit_total_cents = (
               SELECT COALESCE(SUM(unit_price_delta_cents * quantity), 0)
                 FROM order_item_option
                WHERE order_item_id = OLD.order_item_id
           )
     WHERE id = OLD.order_item_id;
END;

/* ---- 13.6 Validacao e contabilizacao de cupons ----------------------------------- */

CREATE TRIGGER trg_coupon_redemption_bi
BEFORE INSERT ON coupon_redemption
FOR EACH ROW
BEGIN
    SELECT RAISE(ABORT, 'Cupom inexistente')
     WHERE NOT EXISTS (SELECT 1 FROM coupon WHERE id = NEW.coupon_id);

    SELECT RAISE(ABORT, 'Cupom inativo')
     WHERE EXISTS (SELECT 1 FROM coupon WHERE id = NEW.coupon_id AND is_active = 0);

    SELECT RAISE(ABORT, 'Cupom fora da validade')
     WHERE EXISTS (
         SELECT 1
           FROM coupon
          WHERE id = NEW.coupon_id
            AND (
                 (starts_at IS NOT NULL AND starts_at > strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
                 OR (ends_at IS NOT NULL AND ends_at < strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
            )
     );

    SELECT RAISE(ABORT, 'Limite total de uso do cupom atingido')
     WHERE EXISTS (
         SELECT 1
           FROM coupon
          WHERE id = NEW.coupon_id
            AND total_usage_limit IS NOT NULL
            AND times_used >= total_usage_limit
     );

    SELECT RAISE(ABORT, 'Limite de uso do cupom por cliente atingido')
     WHERE (
         SELECT COUNT(*)
           FROM coupon_redemption
          WHERE coupon_id = NEW.coupon_id
            AND customer_id = NEW.customer_id
     ) >= (SELECT per_customer_limit FROM coupon WHERE id = NEW.coupon_id);
END;

CREATE TRIGGER trg_coupon_redemption_ai
AFTER INSERT ON coupon_redemption
FOR EACH ROW
BEGIN
    UPDATE coupon
       SET times_used = times_used + 1
     WHERE id = NEW.coupon_id;
END;

CREATE TRIGGER trg_coupon_redemption_ad
AFTER DELETE ON coupon_redemption
FOR EACH ROW
BEGIN
    UPDATE coupon
       SET times_used = CASE WHEN times_used > 0 THEN times_used - 1 ELSE 0 END
     WHERE id = OLD.coupon_id;
END;

/* ---- 13.7 Agregados de avaliacao e entregas -------------------------------------- */

CREATE TRIGGER trg_order_review_store_rating
AFTER INSERT ON order_review
FOR EACH ROW
BEGIN
    UPDATE store
       SET rating_avg = COALESCE((SELECT ROUND(AVG(store_rating), 2) FROM order_review), 0),
           rating_count = (SELECT COUNT(*) FROM order_review)
     WHERE id = 1;
END;

CREATE TRIGGER trg_order_review_courier_rating
AFTER INSERT ON order_review
FOR EACH ROW
WHEN NEW.courier_id IS NOT NULL
BEGIN
    UPDATE courier
       SET rating_avg = COALESCE((
               SELECT ROUND(AVG(courier_rating), 2)
                 FROM order_review
                WHERE courier_id = NEW.courier_id
                  AND courier_rating IS NOT NULL
           ), 5)
     WHERE id = NEW.courier_id;
END;

CREATE TRIGGER trg_courier_delivery_delivered
AFTER UPDATE OF status ON courier_delivery
FOR EACH ROW
WHEN NEW.status = 'DELIVERED' AND OLD.status <> 'DELIVERED'
BEGIN
    UPDATE courier
       SET total_deliveries = total_deliveries + 1
     WHERE id = NEW.courier_id;

    UPDATE customer_order
       SET status_id = (SELECT id FROM order_status WHERE code = 'DELIVERED'),
           delivered_at = COALESCE(delivered_at, strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
           status_note = 'Entrega confirmada pelo entregador',
           status_changed_by_type = 'COURIER',
           status_changed_by_id = NEW.courier_id
     WHERE id = NEW.order_id
       AND status_id <> (SELECT id FROM order_status WHERE code = 'DELIVERED')
       AND status_id NOT IN (SELECT id FROM order_status WHERE code LIKE 'CANCELLED%');
END;

/* =====================================================================================
   14. VIEWS
   ===================================================================================== */

CREATE VIEW vw_menu AS
SELECT
    c.id                                            AS category_id,
    c.name                                          AS category_name,
    c.sort_order                                    AS category_sort_order,
    i.id                                            AS menu_item_id,
    i.name                                          AS item_name,
    i.description                                   AS item_description,
    i.price_cents,
    i.promotional_price_cents,
    COALESCE(i.promotional_price_cents, i.price_cents) AS effective_price_cents,
    i.image_url,
    i.is_available
FROM menu_category c
JOIN menu_item i ON i.menu_category_id = c.id
WHERE c.is_active = 1
  AND i.is_active = 1;

CREATE VIEW vw_order_summary AS
SELECT
    o.id,
    o.order_number,
    o.delivery_type,
    s.code                                          AS status_code,
    s.name                                          AS status_name,
    o.customer_id,
    cu.full_name                                    AS customer_name,
    cu.phone                                        AS customer_phone,
    o.items_subtotal_cents,
    o.delivery_fee_cents,
    o.discount_total_cents,
    o.total_cents,
    o.placed_at,
    o.delivered_at
FROM customer_order o
JOIN customer cu ON cu.id = o.customer_id
JOIN order_status s ON s.id = o.status_id;

CREATE VIEW vw_daily_sales AS
SELECT
    date(o.placed_at, 'localtime') AS sale_date,
    COUNT(*)                       AS orders_count,
    SUM(o.total_cents)             AS revenue_cents,
    SUM(o.delivery_fee_cents)      AS delivery_fees_cents,
    SUM(o.discount_total_cents)    AS discounts_cents
FROM customer_order o
WHERE o.status_id = (SELECT id FROM order_status WHERE code = 'DELIVERED')
GROUP BY date(o.placed_at, 'localtime');

/* =====================================================================================
   15. CARGA INICIAL (AJUSTE OS DADOS DA LOJA ANTES DE USAR EM PRODUCAO)
   ===================================================================================== */

INSERT INTO cuisine_type (id, name) VALUES
    (1, 'Brasileira'),
    (2, 'Japonesa'),
    (3, 'Italiana'),
    (4, 'Lanches'),
    (5, 'Pizzaria'),
    (6, 'Chinesa'),
    (7, 'Arabe'),
    (8, 'Saudavel'),
    (9, 'Doces e Sobremesas'),
    (10, 'Bebidas');

INSERT INTO order_status (id, code, name, sort_order, is_final) VALUES
    (1, 'CREATED',              'Pedido criado',              10, 0),
    (2, 'CONFIRMED',            'Confirmado pela loja',       20, 0),
    (3, 'IN_PREPARATION',       'Em preparo',                 30, 0),
    (4, 'READY',                'Pronto para retirada',       40, 0),
    (5, 'DISPATCHED',           'Em rota de entrega',         50, 0),
    (6, 'DELIVERED',            'Entregue',                   60, 1),
    (7, 'CANCELLED_CUSTOMER',   'Cancelado pelo cliente',     90, 1),
    (8, 'CANCELLED_STORE',      'Cancelado pela loja',        91, 1),
    (9, 'CANCELLED_SYSTEM',     'Cancelado pelo sistema',     92, 1);

INSERT INTO payment_method_type (id, code, name, is_online) VALUES
    (1, 'CREDIT_CARD',   'Cartao de credito',  1),
    (2, 'DEBIT_CARD',    'Cartao de debito',   1),
    (3, 'PIX',           'Pix',                1),
    (4, 'CASH',          'Dinheiro',           0),
    (5, 'MEAL_VOUCHER',  'Vale-refeicao',      1),
    (6, 'FOOD_VOUCHER',  'Vale-alimentacao',   1),
    (7, 'WALLET',        'Carteira digital',   1);

INSERT INTO payment_status (id, code, name, is_final) VALUES
    (1, 'PENDING',             'Aguardando pagamento',   0),
    (2, 'AUTHORIZED',          'Autorizado',             0),
    (3, 'PAID',                'Pago',                   1),
    (4, 'FAILED',              'Falhou',                 1),
    (5, 'REFUNDED',            'Estornado',              1),
    (6, 'PARTIALLY_REFUNDED',  'Estornado parcialmente', 1),
    (7, 'CANCELLED',           'Cancelado',              1),
    (8, 'CHARGEBACK',          'Chargeback',             1);

INSERT INTO order_channel (id, code, name) VALUES
    (1, 'APP',      'Aplicativo'),
    (2, 'WEB',      'Site'),
    (3, 'PHONE',    'Telefone'),
    (4, 'POS',      'Presencial / PDV'),
    (5, 'API',      'Integracao');

INSERT INTO cancellation_reason (id, code, name, responsible) VALUES
    (1, 'CUSTOMER_REQUEST',   'Desistencia do cliente',      'CUSTOMER'),
    (2, 'OUT_OF_STOCK',       'Item sem estoque',            'STORE'),
    (3, 'STORE_CLOSED',       'Loja fechada',                'STORE'),
    (4, 'PREPARATION_DELAY',  'Atraso na preparacao',        'STORE'),
    (5, 'NO_COURIER',         'Sem entregador disponivel',   'STORE'),
    (6, 'ADDRESS_NOT_FOUND',  'Endereco nao localizado',     'COURIER'),
    (7, 'PAYMENT_FAILED',     'Falha no pagamento',          'SYSTEM'),
    (8, 'STORE_ISSUE',        'Problema operacional da loja','STORE');

INSERT INTO vehicle_type (id, code, name) VALUES
    (1, 'MOTORCYCLE', 'Motocicleta'),
    (2, 'BICYCLE',    'Bicicleta'),
    (3, 'CAR',        'Automovel'),
    (4, 'SCOOTER',    'Patinete / Scooter'),
    (5, 'ON_FOOT',    'A pe');

INSERT INTO store (
    id, legal_name, trade_name, document, email, phone, cuisine_type_id,
    street, number, district, city, state, zip_code,
    delivery_fee_base_cents, min_order_value_cents,
    average_prep_minutes, average_delivery_minutes
) VALUES (
    1,
    'Minha Loja de Alimentos Ltda',
    'Minha Loja',
    '00000000000000',
    'contato@minhaloja.com.br',
    '+55 11 99999-9999',
    4,
    'Rua Exemplo',
    '100',
    'Centro',
    'Sao Paulo',
    'SP',
    '01000-000',
    500,
    1500,
    30,
    40
);

INSERT INTO store_opening_hours (day_of_week, open_time, close_time) VALUES
    (0, '11:00', '23:00'),
    (1, '11:00', '23:00'),
    (2, '11:00', '23:00'),
    (3, '11:00', '23:00'),
    (4, '11:00', '23:00'),
    (5, '11:00', '23:00'),
    (6, '11:00', '23:00');

INSERT INTO store_payment_method (payment_method_type_id)
SELECT id FROM payment_method_type WHERE is_active = 1;

COMMIT;

PRAGMA user_version = 1;

/* =====================================================================================
   16. VERIFICACAO POS-EXECUCAO (OPCIONAL)
   =====================================================================================

   -- Quantidade de tabelas de usuario (esperado: 32)
   SELECT COUNT(*) AS tabelas
     FROM sqlite_master
    WHERE type = 'table' AND name NOT LIKE 'sqlite_%';

   -- Carga dos dominios
   SELECT 'order_status' AS tabela, COUNT(*) AS registros FROM order_status
   UNION ALL SELECT 'payment_method_type', COUNT(*) FROM payment_method_type
   UNION ALL SELECT 'payment_status', COUNT(*) FROM payment_status
   UNION ALL SELECT 'order_channel', COUNT(*) FROM order_channel
   UNION ALL SELECT 'cancellation_reason', COUNT(*) FROM cancellation_reason
   UNION ALL SELECT 'vehicle_type', COUNT(*) FROM vehicle_type
   UNION ALL SELECT 'cuisine_type', COUNT(*) FROM cuisine_type;

   ===================================================================================== */

/* ============================== FIM DO SCRIPT ====================================== */
