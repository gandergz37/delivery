# serialize2 - Sistema Cliente-Servidor com Serialização de Linhas

Sistema formado por cliente e servidor com acesso a banco de dados SQLite, que envia o conteúdo de uma linha genérica de qualquer tabela para o cliente usando Java Sockets.

## Características

- **Genérico**: Funciona com qualquer tabela do banco SQLite
- **Suporte a BLOB**: Trata colunas BLOB/BINARY/VARBINARY/LONGVARBINARY corretamente
- **Usa JDK 25**: Conforme solicitado
- **Protocolo customizado**: Envia metadados das colunas + dados da linha

## Estrutura

```
serialize2/
├── pom.xml
└── src/main/java/com/delivery/serialize/
    ├── RowSerializer.java      # Função para serializar linha
    ├── GenericRowServer.java   # Servidor
    └── GenericRowClient.java   # Cliente
```

## Compilação

```bash
mvn clean compile
```

## Execução

1. Inicie o servidor (passando a URL JDBC do SQLite):
```bash
java -cp "target/classes;$(find ~/.m2 -name 'sqlite-jdbc*.jar' 2>/dev/null | head -1)" com.delivery.serialize.GenericRowServer jdbc:sqlite:C:/caminho/para/seu/banco.db
```

2. Em outro terminal, execute o cliente:
```bash
java -cp "target/classes;$(find ~/.m2 -name 'sqlite-jdbc*.jar' 2>/dev/null | head -1)" com.delivery.serialize.GenericRowClient
```

## Funcionamento

O `RowSerializer.serializeRow()` lê qualquer `ResultSet` (linha) e envia:
1. Número de colunas (int)
2. Para cada coluna: nome (UTF), tipo SQL (UTF), tipo JDBC (int)
3. Para cada valor: flag null (boolean) + valor serializado (se não null)

### Tratamento de BLOB

Para colunas BLOB, envia-se o tamanho (int) seguido dos bytes brutos. O cliente exibe `[BLOB] Tamanho: X bytes`.

### Tipos suportados

- **Numéricos**: INTEGER, BIGINT, FLOAT, DOUBLE, NUMERIC/DECIMAL
- **Binários**: BLOB, BINARY, VARBINARY, LONGVARBINARY
- **Booleanos**: BOOLEAN, BIT
- **Texto/Data/Tempo**: VARCHAR, TEXT, CHAR, DATE, TIME, TIMESTAMP (enviados como UTF)
- **NULL**: tratado com flag
