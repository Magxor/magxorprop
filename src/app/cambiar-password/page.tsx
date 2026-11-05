"use client";

import { useEffect, useState, type FormEvent } from "react";
import { supabase } from "@/lib/supabase";

export default function CambiarPasswordPage() {
  const [listo, setListo] = useState(false);
  const [password, setPassword] = useState("");
  const [confirmacion, setConfirmacion] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [cargando, setCargando] = useState(false);
  const [exito, setExito] = useState(false);

  useEffect(() => {
    supabase.auth.getSession().then(({ data: { session } }) => {
      setListo(!!session);
    });
  }, []);

  async function handleSubmit(e: FormEvent<HTMLFormElement>) {
    e.preventDefault();
    setError(null);

    if (password.length < 12) {
      setError("La contraseña debe tener al menos 12 caracteres.");
      return;
    }
    if (password !== confirmacion) {
      setError("Las contraseñas no coinciden.");
      return;
    }

    setCargando(true);
    const { data: { user } } = await supabase.auth.getUser();
    const { error: errorPassword } = await supabase.auth.updateUser({ password });

    if (errorPassword) {
      setCargando(false);
      setError(`No se pudo guardar la contraseña: ${errorPassword.message}`);
      return;
    }

    if (user) {
      await supabase
        .from("usuarios")
        .update({ debe_cambiar_password: false })
        .eq("auth_user_id", user.id);
    }

    setCargando(false);
    setExito(true);
  }

  if (exito) {
    return (
      <main style={{ padding: 40, fontFamily: "sans-serif", maxWidth: 420 }}>
        <h1>Contraseña creada</h1>
        <p>Ya podés ingresar al panel con tu email y la contraseña que definiste.</p>
        <a href="/login">Ir al login</a>
      </main>
    );
  }

  if (!listo) {
    return (
      <main style={{ padding: 40, fontFamily: "sans-serif", maxWidth: 420 }}>
        <h1>Enlace no válido</h1>
        <p>Este enlace venció o ya fue usado. Pedí una nueva invitación.</p>
      </main>
    );
  }

  return (
    <main style={{ padding: 40, fontFamily: "sans-serif", maxWidth: 420 }}>
      <h1>Creá tu contraseña</h1>
      <form onSubmit={handleSubmit}>
        <label>
          Nueva contraseña (mínimo 12 caracteres)
          <input
            type="password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            required
            style={{ display: "block", width: "100%", marginBottom: 12 }}
          />
        </label>
        <label>
          Repetí la contraseña
          <input
            type="password"
            value={confirmacion}
            onChange={(e) => setConfirmacion(e.target.value)}
            required
            style={{ display: "block", width: "100%", marginBottom: 12 }}
          />
        </label>
        <button type="submit" disabled={cargando}>
          {cargando ? "Guardando..." : "Guardar contraseña"}
        </button>
      </form>
      {error && <p style={{ color: "crimson" }}>{error}</p>}
    </main>
  );
}