import io
from datetime import datetime
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt

from reportlab.lib import colors
from reportlab.lib.pagesizes import letter
from reportlab.lib.units import inch
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.platypus import (
    SimpleDocTemplate,
    Paragraph,
    Spacer,
    Table,
    TableStyle,
    Image,
    PageBreak,
)
from reportlab.pdfgen import canvas


# ============================================================
# PAGE NUMBER + FOOTER
# ============================================================

class NumberedCanvas(canvas.Canvas):

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self._saved_page_states = []

    def showPage(self):
        self._saved_page_states.append(dict(self.__dict__))
        self._startPage()

    def save(self):
        page_count = len(self._saved_page_states)

        for state in self._saved_page_states:
            self.__dict__.update(state)
            self.draw_page_number(page_count)
            super().showPage()

        super().save()

    def draw_page_number(self, page_count):
        self.setFont("Helvetica", 8)

        self.drawString(
            36,
            25,
            "NeoPanc AI - Official Report"
        )

        self.drawRightString(
            letter[0] - 36,
            25,
            f"Page {self._pageNumber} of {page_count}"
        )


# ============================================================
# CHART 1 - RISK SCORE
# ============================================================

def create_score_chart(score):

    if score is None:
        return None

    fig, ax = plt.subplots(figsize=(6.5, 2.5))

    ax.barh(
        ["PCRI Score"],
        [score],
        height=0.45,
        color="#3B82F6"
    )

    ax.set_xlim(0, 100)
    ax.set_xlabel("Score / 100")
    ax.set_title("NeoPanc AI Prototype Risk Score")

    ax.text(
        min(score + 2, 95),
        0,
        f"{score:.1f}",
        va="center",
        fontsize=10
    )

    plt.tight_layout()

    image_buffer = io.BytesIO()
    plt.savefig(
        image_buffer,
        format="png",
        dpi=150,
        bbox_inches="tight"
    )

    plt.close(fig)

    image_buffer.seek(0)

    return Image(
        image_buffer,
        width=6.7 * inch,
        height=2.3 * inch
    )


# ============================================================
# CHART 2 - SENSOR VOLTAGES
# ============================================================

def create_sensor_chart(sensor_data):

    names = [
        "TDS",
        "MQ Gas",
        "pH"
    ]

    tds_v = sensor_data.get("tds", {}).get("voltage") or 0.0
    mq_v = sensor_data.get("mq", {}).get("voltage") or 0.0
    ph_v = sensor_data.get("ph", {}).get("voltage") or 0.0

    values = [
        tds_v,
        mq_v,
        ph_v
    ]

    fig, ax = plt.subplots(figsize=(6.5, 3.0))

    ax.bar(
        names,
        values,
        color=["#60A5FA", "#F472B6", "#4ADE80"]
    )

    ax.set_ylabel("Voltage (V)")
    ax.set_title("Live Sensor Voltage Overview")

    for i, value in enumerate(values):
        ax.text(
            i,
            value + 0.05,
            f"{value:.3f} V",
            ha="center",
            va="bottom",
            fontsize=9
        )

    plt.tight_layout()

    image_buffer = io.BytesIO()

    plt.savefig(
        image_buffer,
        format="png",
        dpi=150,
        bbox_inches="tight"
    )

    plt.close(fig)

    image_buffer.seek(0)

    return Image(
        image_buffer,
        width=6.7 * inch,
        height=3.0 * inch
    )


# ============================================================
# MAIN PDF GENERATOR
# ============================================================

def generate_neopanc_report(
    sensor_data,
    output_filename="NeoPanc_Report.pdf",
    report_id="NP-LIVE-001",
    user_id="N/A",
    age="N/A",
    risk_score=None,
    risk_level="N/A",
    confidence=None,
    model_version="NeoPanc AI v1.0",
    survey_data=None
):

    # --------------------------------------------------------
    # CURRENT DATE AND TIME
    # --------------------------------------------------------

    now = datetime.now()

    generated_date = now.strftime("%d %B %Y")
    generated_time = now.strftime("%I:%M:%S %p")

    timestamp = now.strftime(
        "%d %B %Y, %I:%M:%S %p"
    )

    # --------------------------------------------------------
    # PDF DOCUMENT
    # --------------------------------------------------------

    doc = SimpleDocTemplate(
        output_filename,
        pagesize=letter,
        rightMargin=36,
        leftMargin=36,
        topMargin=36,
        bottomMargin=45
    )

    styles = getSampleStyleSheet()

    # --------------------------------------------------------
    # STYLES
    # --------------------------------------------------------

    title_style = ParagraphStyle(
        "NeoPancTitle",
        parent=styles["Title"],
        fontSize=20,
        leading=24,
        alignment=1,
        spaceAfter=8
    )

    subtitle_style = ParagraphStyle(
        "NeoPancSubtitle",
        parent=styles["Normal"],
        fontSize=10,
        leading=13,
        alignment=1,
        spaceAfter=10
    )

    section_style = ParagraphStyle(
        "Section",
        parent=styles["Heading2"],
        fontSize=12,
        leading=15,
        spaceBefore=8,
        spaceAfter=6
    )

    body_style = ParagraphStyle(
        "Body",
        parent=styles["BodyText"],
        fontSize=9,
        leading=13,
        spaceAfter=5
    )

    small_style = ParagraphStyle(
        "Small",
        parent=styles["BodyText"],
        fontSize=8,
        leading=10
    )

    disclaimer_style = ParagraphStyle(
        "Disclaimer",
        parent=styles["BodyText"],
        fontSize=8,
        leading=11
    )

    # --------------------------------------------------------
    # STORY
    # --------------------------------------------------------

    story = []

    # ========================================================
    # PAGE 1
    # ========================================================

    story.append(
        Paragraph(
            "NEOPANC AI",
            title_style
        )
    )

    story.append(
        Paragraph(
            "AI-BASED MULTIMODAL PANCREATIC CANCER RISK SCREENING",
            subtitle_style
        )
    )

    story.append(
        Paragraph(
            "<b>OFFICIAL REPORT</b>",
            subtitle_style
        )
    )

    # --------------------------------------------------------
    # PROTOTYPE BANNER
    # --------------------------------------------------------

    banner_data = [[
        Paragraph(
            "<b>Prototype / Academic Demonstration</b><br/>"
            "This report is generated by a research prototype. "
            "Sensor values and AI outputs must not be presented "
            "as clinically validated diagnostic results.",
            small_style
        )
    ]]

    banner = Table(
        banner_data,
        colWidths=[7.0 * inch]
    )

    banner.setStyle(
        TableStyle([
            (
                "BACKGROUND",
                (0, 0),
                (-1, -1),
                colors.lightgrey
            ),
            (
                "BOX",
                (0, 0),
                (-1, -1),
                0.8,
                colors.grey
            ),
            (
                "LEFTPADDING",
                (0, 0),
                (-1, -1),
                8
            ),
            (
                "RIGHTPADDING",
                (0, 0),
                (-1, -1),
                8
            ),
            (
                "TOPPADDING",
                (0, 0),
                (-1, -1),
                7
            ),
            (
                "BOTTOMPADDING",
                (0, 0),
                (-1, -1),
                7
            ),
        ])
    )

    story.append(banner)

    story.append(Spacer(1, 10))

    # ========================================================
    # 1. REPORT IDENTIFICATION
    # ========================================================

    story.append(
        Paragraph(
            "1. Report Identification",
            section_style
        )
    )

    report_table_data = [
        [
            Paragraph("<b>Report Number</b>", small_style),
            Paragraph(str(report_id), small_style),
            Paragraph("<b>Generated On</b>", small_style),
            Paragraph(generated_date, small_style)
        ],
        [
            Paragraph("<b>Prediction Date</b>", small_style),
            Paragraph(generated_date, small_style),
            Paragraph("<b>Prediction Time</b>", small_style),
            Paragraph(generated_time, small_style)
        ],
        [
            Paragraph("<b>System Version</b>", small_style),
            Paragraph(model_version, small_style),
            Paragraph("<b>Mode</b>", small_style),
            Paragraph("Multi-Sensor Screening", small_style)
        ]
    ]

    report_table = Table(
        report_table_data,
        colWidths=[
            1.35 * inch,
            2.15 * inch,
            1.35 * inch,
            2.15 * inch
        ]
    )

    report_table.setStyle(
        TableStyle([
            ("GRID", (0, 0), (-1, -1), 0.5, colors.grey),
            ("BACKGROUND", (0, 0), (0, -1), colors.whitesmoke),
            ("BACKGROUND", (2, 0), (2, -1), colors.whitesmoke),
            ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
            ("LEFTPADDING", (0, 0), (-1, -1), 6),
            ("RIGHTPADDING", (0, 0), (-1, -1), 6),
            ("TOPPADDING", (0, 0), (-1, -1), 5),
            ("BOTTOMPADDING", (0, 0), (-1, -1), 5),
        ])
    )

    story.append(report_table)

    # ========================================================
    # 2. SUBJECT INFORMATION
    # ========================================================

    story.append(
        Paragraph(
            "2. Subject Information",
            section_style
        )
    )

    subject_table_data = [
        [
            Paragraph("<b>Patient / User ID</b>", small_style),
            Paragraph(str(user_id), small_style),
            Paragraph("<b>Age</b>", small_style),
            Paragraph(str(age), small_style)
        ],
        [
            Paragraph("<b>Email / Contact</b>", small_style),
            Paragraph("Not displayed", small_style),
            Paragraph("<b>Collection Mode</b>", small_style),
            Paragraph("Prototype sensor mode", small_style)
        ],
        [
            Paragraph("<b>Sample Type</b>", small_style),
            Paragraph(
                "Sensor measurement",
                small_style
            ),
            Paragraph("<b>Data Source</b>", small_style),
            Paragraph(
                "Live ESP32 sensor data",
                small_style
            )
        ]
    ]

    subject_table = Table(
        subject_table_data,
        colWidths=[
            1.35 * inch,
            2.15 * inch,
            1.35 * inch,
            2.15 * inch
        ]
    )

    subject_table.setStyle(
        TableStyle([
            ("GRID", (0, 0), (-1, -1), 0.5, colors.grey),
            ("BACKGROUND", (0, 0), (0, -1), colors.whitesmoke),
            ("BACKGROUND", (2, 0), (2, -1), colors.whitesmoke),
            ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
            ("LEFTPADDING", (0, 0), (-1, -1), 6),
            ("RIGHTPADDING", (0, 0), (-1, -1), 6),
            ("TOPPADDING", (0, 0), (-1, -1), 5),
            ("BOTTOMPADDING", (0, 0), (-1, -1), 5),
        ])
    )

    story.append(subject_table)

    # ========================================================
    # 3. AI SCREENING SUMMARY
    # ========================================================

    story.append(
        Paragraph(
            "3. AI Screening Summary",
            section_style
        )
    )

    score_text = (
        f"{risk_score:.1f} / 100"
        if isinstance(risk_score, (int, float))
        else "--"
    )

    confidence_text = (
        f"{confidence:.2f}%"
        if isinstance(confidence, (int, float))
        else "--"
    )

    summary_table_data = [
        [
            Paragraph("<b>PCRI Score</b>", small_style),
            Paragraph(score_text, small_style),
            Paragraph("<b>Prototype Risk Level</b>", small_style),
            Paragraph(str(risk_level), small_style)
        ],
        [
            Paragraph("<b>AI Confidence</b>", small_style),
            Paragraph(confidence_text, small_style),
            Paragraph("<b>Result Type</b>", small_style),
            Paragraph(
                "Risk estimation / screening aid",
                small_style
            )
        ]
    ]

    summary_table = Table(
        summary_table_data,
        colWidths=[
            1.35 * inch,
            2.15 * inch,
            1.35 * inch,
            2.15 * inch
        ]
    )

    summary_table.setStyle(
        TableStyle([
            ("GRID", (0, 0), (-1, -1), 0.5, colors.grey),
            ("BACKGROUND", (0, 0), (0, -1), colors.whitesmoke),
            ("BACKGROUND", (2, 0), (2, -1), colors.whitesmoke),
            ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
            ("LEFTPADDING", (0, 0), (-1, -1), 6),
            ("RIGHTPADDING", (0, 0), (-1, -1), 6),
            ("TOPPADDING", (0, 0), (-1, -1), 5),
            ("BOTTOMPADDING", (0, 0), (-1, -1), 5),
        ])
    )

    story.append(summary_table)

    # --------------------------------------------------------
    # RISK CHART
    # --------------------------------------------------------

    if isinstance(risk_score, (int, float)):
        score_chart = create_score_chart(risk_score)
        if score_chart is not None:
            story.append(Spacer(1, 8))
            story.append(score_chart)

    # ========================================================
    # 4. BIOMARKER & SENSOR READINGS
    # ========================================================

    story.append(
        Paragraph(
            "4. Biomarker & Sensor Readings",
            section_style
        )
    )

    # --------------------------------------------------------
    # SAFE SENSOR VALUE HELPERS
    # --------------------------------------------------------

    tds_info = sensor_data.get("tds", {})
    mq_info = sensor_data.get("mq", {})
    ph_info = sensor_data.get("ph", {})

    tds_raw = tds_info.get("raw", "--")
    tds_voltage = tds_info.get("voltage", None)

    mq_raw = mq_info.get("raw", "--")
    mq_voltage = mq_info.get("voltage", None)

    ph_raw = ph_info.get("raw", "--")
    ph_voltage = ph_info.get("voltage", None)
    ph_value = ph_info.get("ph", None)

    tds_voltage_text = (
        f"{tds_voltage:.3f} V"
        if isinstance(tds_voltage, (int, float))
        else "--"
    )

    mq_voltage_text = (
        f"{mq_voltage:.3f} V"
        if isinstance(mq_voltage, (int, float))
        else "--"
    )

    ph_voltage_text = (
        f"{ph_voltage:.3f} V"
        if isinstance(ph_voltage, (int, float))
        else "--"
    )

    ph_value_text = (
        f"{ph_value:.2f} pH"
        if isinstance(ph_value, (int, float))
        else "--"
    )

    sensor_table_data = [
        [
            Paragraph("<b>Sensor / Channel</b>", small_style),
            Paragraph("<b>Measured Value</b>", small_style),
            Paragraph("<b>Raw ADC</b>", small_style),
            Paragraph("<b>Voltage</b>", small_style)
        ],
        [
            Paragraph("TDS", small_style),
            Paragraph(
                tds_voltage_text,
                small_style
            ),
            Paragraph(
                str(tds_raw),
                small_style
            ),
            Paragraph(
                tds_voltage_text,
                small_style
            )
        ],
        [
            Paragraph("MQ Gas Sensor", small_style),
            Paragraph(
                mq_voltage_text,
                small_style
            ),
            Paragraph(
                str(mq_raw),
                small_style
            ),
            Paragraph(
                mq_voltage_text,
                small_style
            )
        ],
        [
            Paragraph("pH Sensor", small_style),
            Paragraph(
                ph_value_text,
                small_style
            ),
            Paragraph(
                str(ph_raw),
                small_style
            ),
            Paragraph(
                ph_voltage_text,
                small_style
            )
        ]
    ]

    sensor_table = Table(
        sensor_table_data,
        colWidths=[
            2.0 * inch,
            1.55 * inch,
            1.45 * inch,
            2.0 * inch
        ]
    )

    sensor_table.setStyle(
        TableStyle([
            ("GRID", (0, 0), (-1, -1), 0.5, colors.grey),
            ("BACKGROUND", (0, 0), (-1, 0), colors.lightgrey),
            ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
            ("LEFTPADDING", (0, 0), (-1, -1), 6),
            ("RIGHTPADDING", (0, 0), (-1, -1), 6),
            ("TOPPADDING", (0, 0), (-1, -1), 5),
            ("BOTTOMPADDING", (0, 0), (-1, -1), 5),
        ])
    )

    story.append(sensor_table)

    story.append(Spacer(1, 6))

    story.append(
        Paragraph(
            "<i>Sensor values shown above are live prototype readings. "
            "MQ gas-sensor voltage is not presented as calibrated PPM. "
            "pH is shown numerically only when a calibrated pH value is available.</i>",
            small_style
        )
    )

    # ========================================================
    # PAGE 2
    # ========================================================

    story.append(PageBreak())

    # ========================================================
    # SENSOR CHART
    # ========================================================

    story.append(
        Paragraph(
            "Live Sensor Voltage Overview",
            section_style
        )
    )

    sensor_chart = create_sensor_chart(sensor_data)

    story.append(sensor_chart)

    story.append(
        Paragraph(
            "<i>Chart note: this chart is a visual presentation aid, "
            "not a clinical severity or diagnostic chart.</i>",
            small_style
        )
    )

    # ========================================================
    # 5. CLINICAL / USER RISK CHECKLIST
    # ========================================================

    story.append(
        Paragraph(
            "5. Clinical / User Risk Checklist",
            section_style
        )
    )

    surv = survey_data or {}
    def fmt_status(val):
        if val == 1 or val is True: return "Yes"
        if val == 0 or val is False: return "No"
        return "--"

    checklist_data = [
        [
            Paragraph("<b>Risk Metric</b>", small_style),
            Paragraph("<b>Status</b>", small_style),
            Paragraph("<b>Risk Metric</b>", small_style),
            Paragraph("<b>Status</b>", small_style)
        ],
        [
            Paragraph("Smoking history", small_style),
            Paragraph(fmt_status(surv.get('smoking_history')), small_style),
            Paragraph("Diabetes history", small_style),
            Paragraph(fmt_status(surv.get('diabetes')), small_style)
        ],
        [
            Paragraph("Family cancer history", small_style),
            Paragraph(fmt_status(surv.get('family_history')), small_style),
            Paragraph("Unexplained weight loss", small_style),
            Paragraph(fmt_status(surv.get('weight_loss')), small_style)
        ],
        [
            Paragraph(
                "Abdominal pain / back-radiating",
                small_style
            ),
            Paragraph(fmt_status(surv.get('abdominal_pain')), small_style),
            Paragraph(
                "Jaundice / yellowing",
                small_style
            ),
            Paragraph(fmt_status(surv.get('jaundice')), small_style)
        ]
    ]

    checklist_table = Table(
        checklist_data,
        colWidths=[
            2.1 * inch,
            1.3 * inch,
            2.1 * inch,
            1.5 * inch
        ]
    )

    checklist_table.setStyle(
        TableStyle([
            ("GRID", (0, 0), (-1, -1), 0.5, colors.grey),
            ("BACKGROUND", (0, 0), (-1, 0), colors.lightgrey),
            ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
            ("LEFTPADDING", (0, 0), (-1, -1), 6),
            ("RIGHTPADDING", (0, 0), (-1, -1), 6),
            ("TOPPADDING", (0, 0), (-1, -1), 5),
            ("BOTTOMPADDING", (0, 0), (-1, -1), 5),
        ])
    )

    story.append(checklist_table)

    # ========================================================
    # 6. RESULT INTERPRETATION
    # ========================================================

    story.append(
        Paragraph(
            "6. Result Interpretation",
            section_style
        )
    )

    interpretation_text = (
        f"The prototype model output for this sample is "
        f"<b>{risk_level}</b>. It should be interpreted only "
        f"as an output of the NeoPanc AI research prototype "
        f"and does not establish the presence or absence of "
        f"pancreatic cancer."
    )

    story.append(
        Paragraph(
            interpretation_text,
            body_style
        )
    )

    # ========================================================
    # 7. RECOMMENDATIONS / NEXT STEPS
    # ========================================================

    story.append(
        Paragraph(
            "7. Recommendations / Next Steps",
            section_style
        )
    )

    recommendations = [
        "Use the result for research screening and preventive tracking only.",
        "If concerning symptoms or risk factors are present, consult a qualified clinician.",
        "Clinical confirmation, where appropriate, must follow standard medical evaluation.",
        "Retain sensor readings, model version, timestamp and report ID for research traceability."
    ]

    for i, recommendation in enumerate(
        recommendations,
        start=1
    ):
        story.append(
            Paragraph(
                f"{i}. {recommendation}",
                body_style
            )
        )

    # ========================================================
    # 8. SYSTEM VERIFICATION & TRACEABILITY
    # ========================================================

    story.append(
        Paragraph(
            "8. System Verification & Traceability",
            section_style
        )
    )

    trace_table_data = [
        [
            Paragraph("<b>Report ID</b>", small_style),
            Paragraph(str(report_id), small_style)
        ],
        [
            Paragraph("<b>Prediction Timestamp</b>", small_style),
            Paragraph(timestamp, small_style)
        ],
        [
            Paragraph("<b>Generation Timestamp</b>", small_style),
            Paragraph(timestamp, small_style)
        ],
        [
            Paragraph("<b>Model</b>", small_style),
            Paragraph(
                model_version,
                small_style
            )
        ],
        [
            Paragraph("<b>Input Mode</b>", small_style),
            Paragraph(
                "Live ESP32 sensor data",
                small_style
            )
        ],
        [
            Paragraph("<b>Data Source</b>", small_style),
            Paragraph(
                "Prototype sensor system",
                small_style
            )
        ]
    ]

    trace_table = Table(
        trace_table_data,
        colWidths=[
            2.0 * inch,
            5.0 * inch
        ]
    )

    trace_table.setStyle(
        TableStyle([
            ("GRID", (0, 0), (-1, -1), 0.5, colors.grey),
            ("BACKGROUND", (0, 0), (0, -1), colors.whitesmoke),
            ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
            ("LEFTPADDING", (0, 0), (-1, -1), 6),
            ("RIGHTPADDING", (0, 0), (-1, -1), 6),
            ("TOPPADDING", (0, 0), (-1, -1), 5),
            ("BOTTOMPADDING", (0, 0), (-1, -1), 5),
        ])
    )

    story.append(trace_table)

    # ========================================================
    # 9. IMPORTANT DISCLAIMER
    # ========================================================

    story.append(
        Paragraph(
            "9. Important Disclaimer",
            section_style
        )
    )

    disclaimer = (
        "<b>NeoPanc AI is a research prototype and screening aid.</b> "
        "It is not a substitute for clinical diagnosis, pathology, "
        "imaging, laboratory testing, or physician assessment. "
        "Any pancreatic-cancer-related conclusion must be confirmed "
        "through appropriate clinical evaluation. "
        "Sensor readings and AI outputs can be affected by calibration, "
        "sample conditions, environmental factors and dataset limitations."
    )

    disclaimer_table = Table(
        [[
            Paragraph(
                disclaimer,
                disclaimer_style
            )
        ]],
        colWidths=[7.0 * inch]
    )

    disclaimer_table.setStyle(
        TableStyle([
            (
                "BACKGROUND",
                (0, 0),
                (-1, -1),
                colors.whitesmoke
            ),
            (
                "BOX",
                (0, 0),
                (-1, -1),
                0.8,
                colors.grey
            ),
            (
                "LEFTPADDING",
                (0, 0),
                (-1, -1),
                8
            ),
            (
                "RIGHTPADDING",
                (0, 0),
                (-1, -1),
                8
            ),
            (
                "TOPPADDING",
                (0, 0),
                (-1, -1),
                8
            ),
            (
                "BOTTOMPADDING",
                (0, 0),
                (-1, -1),
                8
            ),
        ])
    )

    story.append(disclaimer_table)

    # ========================================================
    # BUILD PDF
    # ========================================================

    doc.build(
        story,
        canvasmaker=NumberedCanvas
    )

    print(
        f"NeoPanc AI report generated successfully: "
        f"{output_filename}"
    )


if __name__ == "__main__":

    sample_sensor_data = {
        "tds": {
            "raw": 587,
            "voltage": 0.473
        },
        "mq": {
            "raw": 276,
            "voltage": 0.222
        },
        "ph": {
            "raw": 0,
            "voltage": 0.0,
            "ph": 7.0
        }
    }

    generate_neopanc_report(
        sensor_data=sample_sensor_data,
        output_filename="NeoPanc_Report.pdf",
        report_id="NP-LIVE-001",
        user_id="N/A",
        age="45",
        risk_score=24.5,
        risk_level="Low",
        confidence=88.5,
        model_version="NeoPanc AI v1.0"
    )
