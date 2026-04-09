import 'package:supabase_flutter/supabase_flutter.dart';

void main() async {
  print('?? Iniciando registro de Santiago Montiel...');
  
  await Supabase.initialize(
    url: 'https://kkzpvlabdxalinhvvxsx.supabase.co',
    anonKey: 'sb_publishable_6hJfBBswU-ScsbSVGljMEQ_cZ5GPxIS',
  );

  try {
    final response = await Supabase.instance.client.auth.signUp(
      email: 'SantiMontiel@gmail.com',
      password: 'Santy321*',
      data: {'display_name': 'Santiago Montiel'},
    );
    
    if (response.user != null) {
      print('? ¡Usuario creado con éxito!');
      print('Nombre: Santiago Montiel');
    }
  } catch (e) {
    print('? Error al crear usuario: \');
  }
  
  // Exit script
  return;
}
