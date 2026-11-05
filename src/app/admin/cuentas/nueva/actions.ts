"use server";

import { supabaseAdmin } from "@/lib/supabase-admin";

type Resultado = { ok: true; mensaje: string } | { ok: false; error: string };

export async function crearCuentaConTitular(
  accessToken: string,
  nombreCuenta: string,
  emailTitular: string
): Promise<Resultado> {
  // 1. Verificar que quien llama tiene sesión y es superadmin
  const { data: { user }, error: errorSesion } = await supabaseAdmin.auth.getUser(accessToken);
  if (errorSesion || !user) return { ok: false, error: "Sesión inválida." };

  const { data: quien } = await supabaseAdmin
    .from("usuarios")
    .select("rol")
    .eq("auth_user_id", user.id)
    .maybeSingle();
  if (quien?.rol !== "superadmin") return { ok: false, error: "No autorizado." };

  // 2. País Argentina
  const { data: pais, error: errorPais } = await supabaseAdmin
    .from("paises")
    .select("id")
    .eq("iso", "AR")
    .single();
  if (errorPais || !pais) return { ok: false, error: "No se encontró Argentina." };

  // 3. Cuenta y país habilitado
  const { data: cuenta, error: errorCuenta } = await supabaseAdmin
    .from("cuentas")
    .insert({ nombre: nombreCuenta, email_titular: emailTitular })
    .select("id")
    .single();
  if (errorCuenta || !cuenta) {
    return { ok: false, error: `Error al crear la cuenta: ${errorCuenta?.message}` };
  }

  const { error: errorPaisCuenta } = await supabaseAdmin
    .from("cuenta_paises")
    .insert({ cuenta_id: cuenta.id, pais_id: pais.id });
  if (errorPaisCuenta) {
    return { ok: false, error: `La cuenta se creó, pero no se habilitó el país: ${errorPaisCuenta.message}` };
  }

  // 4. Invitación por email al titular (él define su contraseña desde el enlace)
  const { data: invitado, error: errorInvitacion } =
    await supabaseAdmin.auth.admin.inviteUserByEmail(emailTitular, {
      redirectTo: "https://inmuebles.magxordigital.com.ar/cambiar-password",
    });
  if (errorInvitacion || !invitado.user) {
    return { ok: false, error: `La cuenta se creó, pero no se pudo enviar la invitación: ${errorInvitacion?.message}` };
  }

  // 5. Vincular al titular con su cuenta
  const { error: errorUsuario } = await supabaseAdmin.from("usuarios").insert({
    auth_user_id: invitado.user.id,
    rol: "titular",
    cuenta_id: cuenta.id,
    nombre: nombreCuenta,
    email: emailTitular,
  });
  if (errorUsuario) {
    return { ok: false, error: `La invitación se envió, pero no se vinculó el usuario: ${errorUsuario.message}` };
  }

  return { ok: true, mensaje: `Cuenta ${cuenta.id} creada. Se envió la invitación a ${emailTitular}.` };
}