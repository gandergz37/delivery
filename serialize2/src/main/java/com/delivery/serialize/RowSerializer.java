package com.delivery.serialize;

import java.io.DataOutputStream;
import java.io.IOException;
import java.sql.ResultSet;
import java.sql.ResultSetMetaData;
import java.sql.SQLException;
import java.sql.Types;

public class RowSerializer {
    
    public static void serializeRow(ResultSet rs, DataOutputStream out) throws SQLException, IOException {
        ResultSetMetaData metaData = rs.getMetaData();
        int columnCount = metaData.getColumnCount();
        
        // Send number of columns
        out.writeInt(columnCount);
        
        // Send column metadata
        for (int i = 1; i <= columnCount; i++) {
            String columnName = metaData.getColumnName(i);
            String columnTypeName = metaData.getColumnTypeName(i);
            int columnType = metaData.getColumnType(i);
            
            out.writeUTF(columnName);
            out.writeUTF(columnTypeName);
            out.writeInt(columnType);
        }
        
        // Send row data
        for (int i = 1; i <= columnCount; i++) {
            int columnType = metaData.getColumnType(i);
            Object value = rs.getObject(i);
            
            if (value == null) {
                out.writeBoolean(true); // null flag
            } else {
                out.writeBoolean(false); // not null
                serializeValue(value, columnType, out);
            }
        }
        out.flush();
    }
    
    private static void serializeValue(Object value, int columnType, DataOutputStream out) throws IOException {
        switch (columnType) {
            case Types.BLOB:
            case Types.BINARY:
            case Types.VARBINARY:
            case Types.LONGVARBINARY:
                if (value instanceof byte[]) {
                    byte[] blobData = (byte[]) value;
                    out.writeInt(blobData.length);
                    out.write(blobData);
                } else {
                    // Try to convert
                    byte[] blobData = value.toString().getBytes();
                    out.writeInt(blobData.length);
                    out.write(blobData);
                }
                break;
            case Types.INTEGER:
            case Types.TINYINT:
            case Types.SMALLINT:
                out.writeInt(((Number) value).intValue());
                break;
            case Types.BIGINT:
                out.writeLong(((Number) value).longValue());
                break;
            case Types.FLOAT:
            case Types.REAL:
                out.writeFloat(((Number) value).floatValue());
                break;
            case Types.DOUBLE:
                out.writeDouble(((Number) value).doubleValue());
                break;
            case Types.NUMERIC:
            case Types.DECIMAL:
                out.writeUTF(value.toString());
                break;
            case Types.BOOLEAN:
            case Types.BIT:
                if (value instanceof Boolean) {
                    out.writeBoolean((Boolean) value);
                } else {
                    out.writeBoolean(((Number) value).intValue() != 0);
                }
                break;
            case Types.DATE:
                out.writeUTF(value.toString());
                break;
            case Types.TIME:
            case Types.TIMESTAMP:
                out.writeUTF(value.toString());
                break;
            default:
                // For TEXT, VARCHAR, CHAR, etc.
                out.writeUTF(value.toString());
                break;
        }
    }
}
