/// Credenciales de Supabase de este proyecto (Ck S de R.L. de C.V.).
///
/// La "anon key" es pública A PROPÓSITO -así funciona Supabase-: es una app
/// de escritorio/móvil sin backend intermedio, así que la clave viaja
/// embebida en el binario igual que viajaba la configuración de Firebase
/// antes. La protección real no es ocultar esta clave (no se puede: cualquiera
/// que abra la app la puede extraer) sino Row Level Security en cada tabla
/// (ver supabase/schema.sql) -acá, con un login propio sin Supabase Auth
/// detrás, la política es "using (true)" para toda operación autenticada con
/// esta clave, igual de abierta que las reglas de Firestore que tenía esta
/// app antes.
class SupabaseConfig {
  static const String url = 'https://rlmjmfjeupwsozppwqwn.supabase.co';
  static const String anonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJsbWptZmpldXB3c296cHB3cXduIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODg2MjU4MTAsImV4cCI6MjEwNDIwMTgxMH0.zYdbhVmuIqmuWRlwHYkcAGfct409tP3FSMORzgd23Cs';
}
