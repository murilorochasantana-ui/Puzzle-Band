/// Hora atual usada pelas telas ("Hoje", ultimos 7 dias, mes). Os testes de
/// imagem (test/goldens_test.dart) fixam um horario para as imagens sairem
/// sempre iguais. O MqttService continua usando DateTime.now().
DateTime Function() relogio = DateTime.now;
