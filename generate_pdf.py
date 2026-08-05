import os
import re
from reportlab.lib.pagesizes import letter
from reportlab.lib import colors
from reportlab.lib.units import inch
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle, PageBreak, HRFlowable
from reportlab.pdfgen import canvas

class NumberedCanvas(canvas.Canvas):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self._saved_page_states = []

    def showPage(self):
        self._saved_page_states.append(dict(self.__dict__))
        self._startPage()

    def save(self):
        num_pages = len(self._saved_page_states)
        for state in self._saved_page_states:
            self.__dict__.update(state)
            self.draw_header_footer(num_pages)
            super().showPage()
        super().save()

    def draw_header_footer(self, page_count):
        if self._pageNumber == 1:
            return  # Skip header/footer on cover page

        self.saveState()
        self.setFont("Helvetica-Bold", 8)
        self.setFillColor(colors.HexColor("#0052CC"))
        self.drawString(54, 11 * inch - 36, "DENTAGURU MOBILE & WEB SYSTEM DOCUMENTATION")
        self.setFont("Helvetica", 8)
        self.setFillColor(colors.HexColor("#64748B"))
        self.drawRightString(8.5 * inch - 54, 11 * inch - 36, "CONFIDENTIAL & PROPRIETARY")

        self.setStrokeColor(colors.HexColor("#CBD5E1"))
        self.setLineWidth(0.5)
        self.line(54, 11 * inch - 42, 8.5 * inch - 54, 11 * inch - 42)

        # Footer
        self.line(54, 46, 8.5 * inch - 54, 46)
        self.setFont("Helvetica", 8)
        self.drawString(54, 32, "© 2026 DentaGuru Healthcare Systems")
        page_str = f"Page {self._pageNumber} of {page_count}"
        self.drawRightString(8.5 * inch - 54, 32, page_str)
        self.restoreState()

def create_pdf(pdf_filename, md_filename):
    doc = SimpleDocTemplate(
        pdf_filename,
        pagesize=letter,
        leftMargin=54,
        rightMargin=54,
        topMargin=54,
        bottomMargin=54
    )

    styles = getSampleStyleSheet()

    # Custom Palette
    c_primary = colors.HexColor("#0052CC")
    c_dark = colors.HexColor("#0F172A")
    c_medium = colors.HexColor("#334155")
    c_orange = colors.HexColor("#FF6B00")
    c_light_bg = colors.HexColor("#F8FAFC")

    title_style = ParagraphStyle(
        'CoverTitle',
        parent=styles['Normal'],
        fontName='Helvetica-Bold',
        fontSize=28,
        leading=34,
        textColor=c_primary,
        alignment=0,
        spaceAfter=10
    )

    subtitle_style = ParagraphStyle(
        'CoverSubTitle',
        parent=styles['Normal'],
        fontName='Helvetica',
        fontSize=14,
        leading=18,
        textColor=c_orange,
        spaceAfter=25
    )

    h1_style = ParagraphStyle(
        'SectionH1',
        parent=styles['Normal'],
        fontName='Helvetica-Bold',
        fontSize=16,
        leading=20,
        textColor=c_primary,
        spaceBefore=18,
        spaceAfter=8,
        keepWithNext=True
    )

    h2_style = ParagraphStyle(
        'SectionH2',
        parent=styles['Normal'],
        fontName='Helvetica-Bold',
        fontSize=12,
        leading=16,
        textColor=c_dark,
        spaceBefore=12,
        spaceAfter=6,
        keepWithNext=True
    )

    body_style = ParagraphStyle(
        'BodyTextCustom',
        parent=styles['Normal'],
        fontName='Helvetica',
        fontSize=9.5,
        leading=14,
        textColor=c_medium,
        spaceAfter=6
    )

    bullet_style = ParagraphStyle(
        'BulletCustom',
        parent=styles['Normal'],
        fontName='Helvetica',
        fontSize=9.5,
        leading=14,
        textColor=c_medium,
        leftIndent=15,
        firstLineIndent=-10,
        spaceAfter=4
    )

    story = []

    # COVER PAGE / HEADER BLOCK
    story.append(Spacer(1, 20))
    story.append(Paragraph("DentaGuru System Documentation", title_style))
    story.append(Paragraph("Complete Technical Architecture & Operation Manual", subtitle_style))
    story.append(HRFlowable(width="100%", thickness=2, color=c_primary, spaceBefore=0, spaceAfter=15))

    with open(md_filename, 'r', encoding='utf-8') as f:
        lines = f.readlines()

    table_data = []
    in_table = False

    for line in lines:
        stripped = line.strip()
        if not stripped:
            continue

        if stripped.startswith('# '):
            story.append(Paragraph(stripped[2:], title_style))
        elif stripped.startswith('## '):
            story.append(Paragraph(stripped[3:], h1_style))
        elif stripped.startswith('### '):
            story.append(Paragraph(stripped[4:], h2_style))
        elif stripped.startswith('|'):
            # Table Row
            in_table = True
            cols = [c.strip() for c in stripped.split('|')[1:-1]]
            if all(set(c).issubset({'-', ':', ' '}) for c in cols if c):
                continue  # Skip separator line
            
            row_cells = []
            for i, col in enumerate(cols):
                is_header = len(table_data) == 0
                f_name = 'Helvetica-Bold' if is_header else 'Helvetica'
                f_color = colors.white if is_header else c_medium
                p_style = ParagraphStyle('TableCell', parent=body_style, fontName=f_name, textColor=f_color, fontSize=9, leading=11)
                
                # Format bold text inside table
                text = re.sub(r'\*\*(.*?)\*\*', r'<b>\1</b>', col)
                row_cells.append(Paragraph(text, p_style))
            table_data.append(row_cells)
        else:
            if in_table and table_data:
                # Render table
                t = Table(table_data, colWidths=[80, 70, 350])
                t.setStyle(TableStyle([
                    ('BACKGROUND', (0,0), (-1,0), c_primary),
                    ('TEXTCOLOR', (0,0), (-1,0), colors.white),
                    ('ALIGN', (0,0), (-1,-1), 'LEFT'),
                    ('VALIGN', (0,0), (-1,-1), 'TOP'),
                    ('INNERGRID', (0,0), (-1,-1), 0.5, colors.HexColor("#CBD5E1")),
                    ('BOX', (0,0), (-1,-1), 0.5, colors.HexColor("#CBD5E1")),
                    ('BACKGROUND', (0,1), (-1,-1), c_light_bg),
                    ('TOPPADDING', (0,0), (-1,-1), 6),
                    ('BOTTOMPADDING', (0,0), (-1,-1), 6),
                ]))
                story.append(t)
                story.append(Spacer(1, 10))
                table_data = []
                in_table = False

            if stripped.startswith('- ') or stripped.startswith('* '):
                formatted = re.sub(r'\*\*(.*?)\*\*', r'<b>\1</b>', stripped[2:])
                story.append(Paragraph(f"• {formatted}", bullet_style))
            elif stripped.startswith('1. ') or stripped.startswith('2. ') or stripped.startswith('3. ') or stripped.startswith('4. ') or stripped.startswith('5. ') or stripped.startswith('6. '):
                formatted = re.sub(r'\*\*(.*?)\*\*', r'<b>\1</b>', stripped[3:])
                story.append(Paragraph(f"{stripped[:3]} {formatted}", bullet_style))
            elif stripped.startswith('---'):
                story.append(HRFlowable(width="100%", thickness=0.5, color=colors.HexColor("#E2E8F0"), spaceBefore=10, spaceAfter=10))
            else:
                formatted = re.sub(r'\*\*(.*?)\*\*', r'<b>\1</b>', stripped)
                story.append(Paragraph(formatted, body_style))

    if in_table and table_data:
        t = Table(table_data, colWidths=[80, 70, 350])
        t.setStyle(TableStyle([
            ('BACKGROUND', (0,0), (-1,0), c_primary),
            ('TEXTCOLOR', (0,0), (-1,0), colors.white),
            ('ALIGN', (0,0), (-1,-1), 'LEFT'),
            ('VALIGN', (0,0), (-1,-1), 'TOP'),
            ('INNERGRID', (0,0), (-1,-1), 0.5, colors.HexColor("#CBD5E1")),
            ('BOX', (0,0), (-1,-1), 0.5, colors.HexColor("#CBD5E1")),
            ('BACKGROUND', (0,1), (-1,-1), c_light_bg),
            ('TOPPADDING', (0,0), (-1,-1), 6),
            ('BOTTOMPADDING', (0,0), (-1,-1), 6),
        ]))
        story.append(t)

    doc.build(story, canvasmaker=NumberedCanvas)
    print(f"SUCCESS: PDF Generated at {pdf_filename}")

if __name__ == '__main__':
    md_file = r"c:\Users\ADMIN\Desktop\project tpc\Dentaguru\DentaGuru_Complete_Documentation.md"
    pdf_file = r"c:\Users\ADMIN\Desktop\project tpc\Dentaguru\DentaGuru_Documentation.pdf"
    create_pdf(pdf_file, md_file)
