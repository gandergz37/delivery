# serialize — cliente/servidor TCP + SQLite (Java puro, javac)

Projeto de exemplo em que um **servidor** acessa um banco **SQLite** e envia para o
**cliente**, via socket TCP, o conteúdo de **uma linha qualquer de uma tabela genérica**.

Nada no código conhece o esquema do banco: o nome da tabela e da coluna-chave são
recebidos do cliente e as colunas da linha são descobertas em tempo de execução com
`ResultSetMetaData`. Funciona com qualquer tabela existente no banco.

---

## Estrutura

```
serialize/
├── build.bat                  compila tudo com javac (gera out/)
├── run-server.bat             sobe o servidor
├── run-client.bat             executa o cliente
├── db/demo.db                 banco de exemplo (criado automaticamente no 1º start)
├── lib/sqlite-jdbc-3.54.1.0.jar   driver JDBC do SQLite
└── src/
    ├── protocol/
    │   └── RowProtocol.java       formato das mensagens (tamanho + UTF-8)
    ├── server/
    │   ├── RowServer.java         ServerSocket + uma thread por cliente
    │   ├── RowSender.java         >>> A FUNÇÃO PEDIDA <<<
    │   ├── SqliteRowRepository.java   SELECT genérico (tabela/coluna dinâmicas)
    │   └── DemoDatabase.java      cria tabelas e dados de exemplo
    └── client/
        └── RowClient.java         conecta, envia o pedido e imprime a linha
```

---

## Requisitos

* JDK 17 ou superior (`javac` e `java` no PATH, ou `JAVA_HOME` definido)
* Nenhuma ferramenta de build: tudo é compilado com `javac`
* O driver `lib/sqlite-jdbc-3.54.1.0.jar` já está incluído

---

## Compilar e executar

```bat
build.bat
run-server.bat
```

Em outro terminal:

```bat
run-client.bat clientes id 2
run-client.bat produtos id 10
run-client.bat produtos id 10 192.168.0.10 5555
```

Sem argumentos, o cliente entra em modo interativo:

```bat
run-client.bat
```

O servidor aceita porta e caminho do banco:

```bat
run-server.bat 5555 db/demo.db
```

Saída esperada:

```
Linha recebida de clientes (5 colunas):
  id     : 2
  nome   : Bruno Lima
  email  : bruno@exemplo.com
  cidade : Recife
  ativo  : 1
```

Casos de borda também são tratados:

```
Nenhuma linha em 'clientes' com id = '999'.
Erro retornado pelo servidor: [SQLITE_ERROR] SQL error or missing database (no such table: ...)
```

---

## A função pedida

Está em `src/server/RowSender.java`:

```java
public static void sendRow(Socket socket,
                           SqliteRowRepository repository,
                           String table,
                           String keyColumn,
                           String keyValue) throws IOException
```

O que ela faz:

1. Busca a linha com `SELECT * FROM "tabela" WHERE "coluna" = ? LIMIT 1`
   (identificadores escapados, valor como parâmetro — sem SQL Injection).
2. Se a linha não existir, envia o status `NOT_FOUND`.
3. Se existir, envia `OK`, a quantidade de colunas e, para cada coluna,
   o nome, um indicador de NULL e o valor.
4. Se o banco recusar o pedido (tabela inexistente, por exemplo), envia `ERROR`
   com a mensagem.

Há também um atalho que recebe apenas o caminho do banco:

```java
RowSender.sendRow(socket, "db/demo.db", "clientes", "id", "2");
```

### Por que funciona para qualquer tabela

* `SELECT *` + `ResultSetMetaData` → as colunas e os valores vêm do próprio resultado.
* `getString(i)` devolve `null` para colunas NULL; o protocolo sinaliza isso com um `boolean`.
* A conexão é aberta por requisição, então vários clientes podem ser atendidos ao mesmo
  tempo sem compartilhar um `Connection` (o que não é seguro no SQLite JDBC).

---

## Protocolo (TCP, porta padrão 5555)

Cada string trafega como `int tamanhoEmBytes` + bytes UTF-8 (`-1` = NULL). Isso permite
acentos, quebras de linha e aspas sem precisar de escaping.

**Requisição** (cliente → servidor)

| Ordem | Campo      | Tipo   |
|-------|------------|--------|
| 1     | tabela     | string |
| 2     | colunaChave| string |
| 3     | valor      | string |

**Resposta** (servidor → cliente)

| Status | Significado | Payload |
|--------|-------------|---------|
| `0` OK | linha encontrada | `int n`, depois `n` × (`string nome`, `boolean naoNulo`, [`string valor`]) |
| `1` NOT_FOUND | nenhuma linha | — |
| `2` ERROR | falha no servidor | `string mensagem` |

O cliente fecha a conexão depois de ler uma resposta (uma requisição por conexão).
O servidor usa um pool de threads, então conexões simultâneas são atendidas em paralelo.

---

## Adaptando para outra tabela

Não é preciso recompilar nem alterar o servidor. Basta passar outros nomes:

```bat
run-client.bat nome_da_tabela nome_da_coluna valor
```

Exemplos com o banco de exemplo:

```bat
run-client.bat produtos nome "Mouse Sem Fio"
run-client.bat clientes cidade Curitiba
```

> Observação: a comparação usa o tipo dinâmico do SQLite, então uma coluna `INTEGER`
> pode ser consultada com `"10"` sem problema (a afinidade da coluna converte o valor).

---

## Observações

* `db/demo.db` é criado automaticamente na primeira execução do servidor
  (tabelas `clientes` e `produtos`). Apague o arquivo para recriar os dados.
* Para usar outro banco, passe o caminho: `run-server.bat 5555 C:\caminho\banco.db`.
* O `sqlite-jdbc` precisa estar no *classpath* em tempo de compilação e de execução —
  os scripts `.bat` já fazem isso.
* Os scripts usam `chcp 65001` e `-Dfile.encoding=UTF-8` para acentos no console.
