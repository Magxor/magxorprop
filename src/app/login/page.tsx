"use client";

import { useState, type FormEvent } from "react";
import { supabase } from "@/lib/supabase";

export default function LoginPage() {
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [cargando, setCargando] = useState(false);
  const [rol, setRol] = useState<string | null>(null);

  async function handleSubmit(e: FormEvent<HTMLFormElement>) {
    e.preventDefault();
    setError(null);
    setRol(null);
    setCargando(true);

    const { error } = await supabase.auth.signInWithPassword({ email, password });
    if (error) {
      setCargando(false);
      setError("Email o contraseña incorrectos.");
      return;
    }

    const { data: { user } } = await supabase.auth.getUser();
    const { data: fila, error: errorFila } = await supabase
      .from("usuarios")
      .select("rol")
      .eq("auth_user_id", user?.id ?? "")
      .maybeSingle();

    setCargando(false);
    if (errorFila) {
      setError(`Error al leer usuarios: ${errorFila.message}`);
      return;
    }
    if (!fila) {
      setError("Tu usuario de acceso no está vinculado a ninguna cuenta.");
      return;
    }
    setRol(fila.rol);
  }

  return (
    <main style={{ padding: 40, fontFamily: "sans-serif", maxWidth: 360 }}>
      <h1>Ingresar</h1>
      <form onSubmit={handleSubmit}>
        <label>
          Email
          <input
            type="email"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            required
            style={{ display: "block", width: "100%", marginBottom: 12 }}
          />
        </label>
        <label>
          Contraseña
          <input
            type="password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            required
            style={{ display: "block", width: "100%", marginBottom: 12 }}
          />
        </label>
        <button type="submit" disabled={cargando}>
          {cargando ? "Ingresando..." : "Ingresar"}
        </button>
      </form>
      {error && <p style={{ color: "crimson" }}>{error}</p>}
      {rol && <p>Ingreso correcto. Rol: <strong>{rol}</strong></p>}
    </main>
  );
}