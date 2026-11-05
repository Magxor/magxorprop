"use client";

import { useState, type FormEvent } from "react";
import { supabase } from "@/lib/supabase";
import { crearCuentaConTitular } from "./actions";

export default function NuevaCuentaPage() {
  const [nombre, setNombre] = useState("");
  const [emailTitular, setEmailTitular] = useState("");
  const [cargando, setCargando] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [mensaje, setMensaje] = useState<string | null>(null);

  async function handleSubmit(e: FormEvent<HTMLFormElement>) {
    e.preventDefault();
    setError(null);
    setMensaje(null);
    setCargando(true);

    const { data: { session } } = await supabase.auth.getSession();
    if (!session) {
      setCargando(false);
      setError("Tu sesión expiró. Volvé a iniciar sesión.");
      return;
    }

    const resultado = await crearCuentaConTitular(
      session.access_token,
      nombre,
      emailTitular
    );

    setCargando(false);
    if (!resultado.ok) {
      setError(resultado.error);
      return;
    }
    setMensaje(resultado.mensaje);
    setNombre("");
    setEmailTitular("");
  }

  return (
    <main style={{ padding: 40, fontFamily: "sans-serif", maxWidth: 420 }}>
      <h1>Nueva cuenta</h1>
      <form onSubmit={handleSubmit}>
        <label>
          Nombre de la cuenta
          <input
            value={nombre}
            onChange={(e) => setNombre(e.target.value)}
            required
            style={{ display: "block", width: "100%", marginBottom: 12 }}
          />
        </label>
        <label>
          Email del titular
          <input
            type="email"
            value={emailTitular}
            onChange={(e) => setEmailTitular(e.target.value)}
            required
            style={{ display: "block", width: "100%", marginBottom: 12 }}
          />
        </label>
        <button type="submit" disabled={cargando}>
          {cargando ? "Creando..." : "Crear cuenta"}
        </button>
      </form>
      {error && <p style={{ color: "crimson" }}>{error}</p>}
      {mensaje && <p>{mensaje}</p>}
    </main>
  );
}