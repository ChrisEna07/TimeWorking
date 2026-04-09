import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/work_log.dart';
import '../config/app_config.dart';

class PdfService {
  static Future<void> generateAndShareReport(List<WorkLog> logs, double totalPayable, double hourlyRate) async {
    final pdf = pw.Document();
    
    final currencyFormatter = NumberFormat.currency(locale: 'es_CO', symbol: '\$', decimalDigits: 0);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (context) => [
          pw.Header(
            level: 0,
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(AppConfig.appName, style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold, color: PdfColors.green900)),
                    pw.Text('Reporte de Horas Trabajadas', style: const pw.TextStyle(fontSize: 14, color: PdfColors.grey700)),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text('Fecha: ${DateFormat('dd/MM/yyyy').format(DateTime.now())}'),
                    pw.Text('Desarrollado por: ${AppConfig.developer}'),
                  ],
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 20),
          
          pw.TableHelper.fromTextArray(
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.green900),
            cellAlignment: pw.Alignment.center,
            headers: ['Día', 'Entrada', 'Salida', 'Horas', 'Total Dia'],
            data: logs.map((log) {
              return [
                log.formattedDate + (log.isSaturday ? " (Sab)" : ""),
                log.formattedStartTime,
                log.formattedEndTime,
                log.totalHours.toStringAsFixed(2),
                currencyFormatter.format(log.totalHours * hourlyRate),
              ];
            }).toList(),
          ),
          
          pw.SizedBox(height: 30),
          pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: const pw.BoxDecoration(
              color: PdfColors.grey100,
              borderRadius: pw.BorderRadius.all(pw.Radius.circular(5)),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('Fórmula de Cálculo Preciso:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                pw.Text('1. Bruto: (Hora de Salida - Hora de Entrada)', style: const pw.TextStyle(fontSize: 9)),
                pw.Text('2. Neto: (Tiempo Bruto - Minutos de Almuerzo)', style: const pw.TextStyle(fontSize: 9)),
                pw.Text('3. Pago: (Horas Netas x ${currencyFormatter.format(hourlyRate)})', style: const pw.TextStyle(fontSize: 9)),
                pw.Text('* Los cálculos se realizan con precisión de segundos para asegurar que cada minuto trabajado sea pagado exactamente.', 
                  style: pw.TextStyle(fontSize: 8, fontStyle: pw.FontStyle.italic, color: PdfColors.grey700)),
              ],
            ),
          ),
          
          pw.SizedBox(height: 20),
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Container(
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.green900, width: 2),
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text('TOTAL A PAGAR ESTE SEMANA:', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
                  pw.Text(currencyFormatter.format(totalPayable * hourlyRate), style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold, color: PdfColors.green900)),
                  pw.Text('(Excluye sábado de esta semana)', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
                ],
              ),
            ),
          ),
          
          pw.Footer(
            leading: pw.Text('TimeWorking by ChrizDev', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey)),
          ),
        ],
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'Reporte_TimeWorking_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf',
    );
  }
}
