package com.delivery.serialize;

import java.io.DataInputStream;
import java.io.IOException;
import java.net.Socket;
import java.sql.Types;

public class GenericRowClient {
    private static final String HOST = "localhost";
    private static final int PORT = 12345;
    
    public static void main(String[] args) {
        try (Socket socket = new Socket(HOST, PORT);
             DataInputStream in = new DataInputStream(socket.getInputStream())) {
            
            System.out.println("Conectado ao servidor");
            
            // Read number of columns
            int columnCount = in.readInt();
            System.out.println("Numero de colunas: " + columnCount);
            System.out.println("==================================================");
            
            // Read column metadata
            String[] columnNames = new String[columnCount];
            String[] columnTypeNames = new String[columnCount];
            int[] columnTypes = new int[columnCount];
            
            for (int i = 0; i < columnCount; i++) {
                columnNames[i] = in.readUTF();
                columnTypeNames[i] = in.readUTF();
                columnTypes[i] = in.readInt();
                System.out.println("Coluna " + (i + 1) + ": " + columnNames[i] + " (" + columnTypeNames[i] + ")");
            }
            System.out.println("==================================================");
            System.out.println("DADOS DA LINHA:");
            System.out.println("==================================================");
            
            // Read row data
            for (int i = 0; i < columnCount; i++) {
                boolean isNull = in.readBoolean();
                System.out.print(columnNames[i] + ": ");
                
                if (isNull) {
                    System.out.println("NULL");
                } else {
                    switch (columnTypes[i]) {
                        case Types.BLOB:
                        case Types.BINARY:
                        case Types.VARBINARY:
                        case Types.LONGVARBINARY:
                            int blobLength = in.readInt();
                            byte[] blobData = new byte[blobLength];
                            in.readFully(blobData);
                            System.out.println("[BLOB] Tamanho: " + blobLength + " bytes");
                            break;
                        case Types.INTEGER:
                        case Types.TINYINT:
                        case Types.SMALLINT:
                            System.out.println(in.readInt());
                            break;
                        case Types.BIGINT:
                            System.out.println(in.readLong());
                            break;
                        case Types.FLOAT:
                        case Types.REAL:
                            System.out.println(in.readFloat());
                            break;
                        case Types.DOUBLE:
                            System.out.println(in.readDouble());
                            break;
                        case Types.NUMERIC:
                        case Types.DECIMAL:
                        case Types.BOOLEAN:
                        case Types.BIT:
                        case Types.DATE:
                        case Types.TIME:
                        case Types.TIMESTAMP:
                        default:
                            System.out.println(in.readUTF());
                            break;
                    }
                }
            }
            System.out.println("==================================================");
            
        } catch (IOException e) {
            e.printStackTrace();
        }
    }
}
