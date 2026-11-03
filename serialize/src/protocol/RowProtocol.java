package protocol;

import java.io.DataInputStream;
import java.io.DataOutputStream;
import java.io.IOException;
import java.nio.charset.StandardCharsets;

/**
 * Protocolo binário simples compartilhado entre cliente e servidor.
 *
 * <p>Formato da requisição (cliente -> servidor):
 * <pre>
 *   string table
 *   string keyColumn
 *   string keyValue
 * </pre>
 *
 * <p>Formato da resposta (servidor -> cliente):
 * <pre>
 *   byte status
 *     0 = OK        -> int quantidadeDeColunas, depois para cada coluna:
 *                      string nome, boolean valorNaoNulo, [string valor]
 *     1 = NOT_FOUND -> nenhuma linha corresponde à chave
 *     2 = ERROR     -> string mensagemDeErro
 * </pre>
 *
 * <p>Uma "string" é gravada como {@code int tamanho} (bytes UTF-8) seguido dos bytes.
 * O tamanho -1 representa {@code null}. Assim qualquer conteúdo (acentos, quebras de
 * linha, aspas, etc.) trafega sem problemas, sem precisar de escaping.
 */
public final class RowProtocol {

    /** A linha foi encontrada e enviada. */
    public static final byte STATUS_OK = 0;
    /** Nenhuma linha corresponde à chave informada. */
    public static final byte STATUS_NOT_FOUND = 1;
    /** O servidor não conseguiu atender o pedido (tabela inexistente, SQL inválido, etc.). */
    public static final byte STATUS_ERROR = 2;

    /** Limite de segurança para não alocar memória demais com um tamanho corrompido. */
    private static final int MAX_STRING_BYTES = 8 * 1024 * 1024;

    private RowProtocol() {
        // classe utilitária
    }

    public static void writeString(DataOutputStream out, String value) throws IOException {
        if (value == null) {
            out.writeInt(-1);
            return;
        }
        byte[] bytes = value.getBytes(StandardCharsets.UTF_8);
        out.writeInt(bytes.length);
        out.write(bytes);
    }

    public static String readString(DataInputStream in) throws IOException {
        int length = in.readInt();
        if (length < 0) {
            return null;
        }
        if (length > MAX_STRING_BYTES) {
            throw new IOException("String maior que o limite do protocolo: " + length + " bytes");
        }
        byte[] bytes = new byte[length];
        in.readFully(bytes);
        return new String(bytes, StandardCharsets.UTF_8);
    }
}
