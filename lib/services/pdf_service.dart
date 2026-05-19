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
            headers: ['Día', 'Entrada / Tipo', 'Salida', 'Horas', 'Total Dia'],
            data: logs.map((log) {
              String typeStr = log.formattedStartTime;
              if (log.workMode == 'shift_8') {
                typeStr = "Jornada 8h";
              } else if (log.workMode == 'shift_12') {
                typeStr = "Jornada 12h";
              } else if (log.workMode == 'custom') {
                typeStr = "Jornada Pers.";
              }
              return [
                log.formattedDate + (log.isSaturday ? " (Sab)" : ""),
                typeStr,
                log.workMode == 'hours' ? log.formattedEndTime : "Fija",
                log.totalHours.toStringAsFixed(2),
                currencyFormatter.format(log.totalHours * hourlyRate),
              ];
            }).toList(),
          ),
          
          pw.SizedBox(height: 20),
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
                pw.Text('1. Bruto: (Hora de Salida - Hora de Entrada) (Si es modo por horas)', style: const pw.TextStyle(fontSize: 9)),
                pw.Text('2. Neto: (Tiempo Bruto - Minutos de Almuerzo) o Jornada Plana configurada', style: const pw.TextStyle(fontSize: 9)),
                pw.Text('3. Pago: (Horas Netas x ${currencyFormatter.format(hourlyRate)})', style: const pw.TextStyle(fontSize: 9)),
              ],
            ),
          ),
          
          pw.SizedBox(height: 20),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Prestaciones box (left)
              pw.Container(
                width: 250,
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey400),
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('Estimación de Prestaciones Sociales (Col):', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
                    pw.SizedBox(height: 5),
                    _pdfBenefitRow('Prima de Servicios (8.33%):', totalPayable * hourlyRate * 0.0833, currencyFormatter),
                    _pdfBenefitRow('Cesantías (8.33%):', totalPayable * hourlyRate * 0.0833, currencyFormatter),
                    _pdfBenefitRow('Intereses s/ Cesantías (1.00%):', totalPayable * hourlyRate * 0.01, currencyFormatter),
                    _pdfBenefitRow('Vacaciones (4.17%):', totalPayable * hourlyRate * 0.0417, currencyFormatter),
                    pw.Divider(color: PdfColors.grey300),
                    _pdfBenefitRow('Total Prestaciones (21.83%):', totalPayable * hourlyRate * 0.2183, currencyFormatter, isBold: true),
                  ],
                ),
              ),
              
              // Total box (right)
              pw.Container(
                width: 230,
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.green900, width: 2),
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text('TOTAL NETO TRABAJADO:', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                    pw.Text(currencyFormatter.format(totalPayable * hourlyRate), style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: PdfColors.green900)),
                    pw.Text('(Excluye sábado de esta semana)', style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600)),
                    pw.SizedBox(height: 10),
                    pw.Text('TOTAL NETO + PRESTACIONES:', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                    pw.Text(currencyFormatter.format(totalPayable * hourlyRate * 1.2183), style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: PdfColors.green900)),
                  ],
                ),
              ),
            ],
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

  static pw.Widget _pdfBenefitRow(String label, double value, NumberFormat formatter, {bool isBold = false}) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(label, style: pw.TextStyle(fontSize: 8, fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal)),
        pw.Text(formatter.format(value), style: pw.TextStyle(fontSize: 8, fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal)),
      ],
    );
  }
}
