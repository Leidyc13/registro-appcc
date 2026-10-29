# Registro APPCC

Herramienta web para llevar el APPCC de obradores y pymes alimentarias sin papeles.

- Cuentas con email y contraseña; cada obrador ve solo sus datos.
- Equipo de trabajo con código de invitación (responsable y empleados).
- Control de temperaturas con alertas y acción correctiva obligatoria.
- Plan de limpieza diario y semanal configurable.
- Recepción de materias primas con lote, caducidad y los 14 alérgenos.
- Lotes de producción que heredan los alérgenos de sus ingredientes.
- Trazabilidad hacia atrás y hacia delante.
- Incidencias con cierre registrado e informes CSV para inspección.
- Los registros no se pueden editar ni borrar: quedan como evidencia, con autor y hora.

## Archivos
- `index.html`: la aplicación.
- `config.js`: conexión con Supabase (URL y clave pública anon).
- `supabase.sql`: base de datos y reglas de seguridad. Se ejecuta una vez en Supabase.

Desarrollado por Leidy Mariana Cabeza Rendón · leidycabezare@gmail.com
