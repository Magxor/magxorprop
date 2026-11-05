"use client";

import { useEffect, useState } from "react";
import { supabase } from "@/lib/supabase";

export default function AdminPage() {
  const [estado, setEstado] = useState<"cargando" | "ok" | "no-autorizado">("cargando");
  const [nombre, setNombre] = useState<string>("");

  useEffect(() => {
    async function verificar() {
      const { data: { user } } = await supabase.auth.getUser();
      if (!user) {
        setEstado("no-autorizado");
        return;
      }

      const { data: fila } = await supabase
        .from("usuarios")
        .select("rol, nombre")
        .eq("auth_user_id", user.id)
        .maybeSingle();

      if (fila?.rol === "superadmin") {
        setNombre(fila.nombre);
        setEstado("ok");
      } else {
        setEstado("no-autorizado");
      }
    }
    verificar();
  }, []);

  if (estado === "cargando") {
    return <main style={{ padding: 40, fontFamily: "sans-serif" }}>Verificando acceso...</main>;
  }

  if (estado === "no-autorizado") {
    return (
      <main style={{ padding: 40, fontFamily: "sans-serif" }}>
        <h1>Acceso restringido</h1>
        <p>Necesitás iniciar sesión como superadmin.</p>
        <a href="/login">Ir al login</a>
      </main>
    );
  }

  return (
    <main style={{ padding: 40, fontFamily: "sans-serif" }}>
      <h1>Panel del superadmin</h1>
      <p>Bienvenido, {nombre}.</p>
    </main>
  );
}