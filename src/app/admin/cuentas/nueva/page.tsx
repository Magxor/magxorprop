"use client";

import { useState, type FormEvent } from "react";
import { supabase } from "@/lib/supabase";

export default function NuevaCuentaPage() {
  const [nombre, setNombre] = useState("");
  const [emailTitular, setEmailTitular] = useState("");
  const [cargando, setCargando] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [creada, setCreada] = useState<string | null>(null);

  async function handleSubmit(e: FormEvent<HTMLFormElement>) {
    e.preventDefault();
    setError(null);
    setCreada(null);
    setCargando(true);

    const { data: pais, error: errorPais } = await supabase
      .from("paises")
      .select("id")
      .eq("iso", "AR")
      .single();

    if (errorPais || !pais) {
      setCargando(false);
      setError(`No se encontró Argentina: ${errorPais?.message ?? ""}`);
      return;
    }

    const { data: cuenta, error: errorCuenta } = await supabase
      .from("cuentas")
      .insert({ nombre, email_titular: emailTitular })
      .select("id")
      .single();

    if (errorCuenta || !cuenta) {
      setCargando(false);
      setError(`Error al crear la cuenta: ${errorCuenta?.message ?? ""}`);
      return;
    }

    const { error: errorPaises } = await supabase
      .from("cuenta_paises")
      .insert({ cuenta_id: cuenta.id, pais_id: pais.id });

    setCargando(false);
    if (errorPaises) {
      setError(`La cuenta se creó, pero no se pudo habilitar el país: ${errorPaises.message}`);
      return;
    }

    setCreada(`Cuenta creada (id ${cuenta.id}) con Argentina habilitada.`);
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
      {creada && <p>{creada}</p>}
    </main>
  );
}