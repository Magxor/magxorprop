import { Suspense } from "react";
import { supabase } from "@/lib/supabase";

async function ConteoPaises() {
  const { data, error } = await supabase
    .from("paises")
    .select("nombre, habilitado");

  if (error) return <p>Error: {error.message}</p>;
  return <p>Filas visibles con clave pública: {data?.length ?? 0}</p>;
}

export default function TestDb() {
  return (
    <main style={{ padding: 40, fontFamily: "sans-serif" }}>
      <h1>Prueba de conexión</h1>
      <Suspense fallback={<p>Consultando Supabase...</p>}>
        <ConteoPaises />
      </Suspense>
    </main>
  );
}