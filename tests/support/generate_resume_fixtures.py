"""Opt-in fictional fixture generator; no IO on import, no network or models."""
from datetime import datetime, timezone
from hashlib import sha256
from io import BytesIO
import argparse
import json
from pathlib import Path
from zipfile import ZipFile, ZipInfo, ZIP_DEFLATED

TEXT = '''Education
Cedar University | BSc Computing | Expected 2027 | GPA: 3.8/4.0
Pine College | Diploma Statistics | Completed 2023 | GPA: 3.6/4.0
Experience
Harbor Labs | Engineering Intern | June-August 2024
- I implemented a queue using Python.
- Our team reduced handoff errors.
Summit Clinic | Analyst Intern | May-August 2023
- I wrote SQL validation checks.
Projects
Nurse Handoff | 2024
- I designed the review workflow in R.
Atlas Monitor | 2023
- My teammate built the metrics dashboard.
Fictional Northstar | Expected 2027
- I implemented validation tests using R.
Skills
Languages: Python, SQL, C++, R
Certifications
Data Foundations | Cedar Institute | In progress
Applied Statistics | Pine Institute | Awarded 2024
Summary
Student interested in reliable systems.
'''


def pdf_bytes(text):
    # Original minimal one-column selectable text fixture, built-in PDF font.
    # No embedded competitor assets, fonts, images or external dependencies.
    commands = ['BT', '/F1 11 Tf', '45 755 Td']
    for index, line in enumerate(text.splitlines()):
        if index: commands.append('0 -18 Td')
        escaped = line.replace('\\', '\\\\').replace('(', '\\(').replace(')', '\\)')
        commands.append('('+escaped+') Tj')
    stream = ('\n'.join(commands)+'\nET\n').encode('ascii')
    objects = [b'<< /Type /Catalog /Pages 2 0 R >>',
        b'<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
        b'<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>',
        b'<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
        b'<< /Length '+str(len(stream)).encode()+b' >>\nstream\n'+stream+b'endstream']
    data = bytearray(b'%PDF-1.4\n% Fictional Relay resume fixture\n'); offsets = [0]
    for index, value in enumerate(objects, 1):
        offsets.append(len(data)); data.extend(str(index).encode()+b' 0 obj\n'+value+b'\nendobj\n')
    xref = len(data); data.extend(b'xref\n0 6\n0000000000 65535 f \n')
    for offset in offsets[1:]: data.extend(f'{offset:010d} 00000 n \n'.encode())
    data.extend(b'trailer\n<< /Size 6 /Root 1 0 R >>\nstartxref\n'+str(xref).encode()+b'\n%%EOF\n')
    return bytes(data)


def docx_bytes(text):
    from docx import Document  # Existing optional pinned dependency, only on explicit generation.
    document = Document()
    properties = document.core_properties
    properties.author = 'Relay fictional test fixture'
    properties.title = 'Fictional resume coverage'
    properties.created = properties.modified = datetime(2026, 10, 23, tzinfo=timezone.utc)
    for line in text.splitlines(): document.add_paragraph(line)
    raw = BytesIO(); document.save(raw); result = BytesIO()
    with ZipFile(BytesIO(raw.getvalue())) as source, ZipFile(result, 'w', ZIP_DEFLATED) as target:
        for name in sorted(source.namelist()):
            info = ZipInfo(name, date_time=(2026, 10, 23, 0, 0, 0)); info.compress_type = ZIP_DEFLATED
            target.writestr(info, source.read(name))
    return result.getvalue()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args(); args.output.mkdir(parents=True, exist_ok=True)
    files = {'fictional-linear.txt': TEXT.encode(), 'fictional-linear.pdf': pdf_bytes(TEXT),
             'fictional-linear.docx': docx_bytes(TEXT)}
    for name, data in files.items(): (args.output/name).write_bytes(data)
    manifest = {'schema_version': 1, 'fictional': True,
        'files': {name: {'sha256': sha256(data).hexdigest(), 'size': len(data)} for name, data in files.items()}}
    (args.output/'manifest.json').write_text(json.dumps(manifest, indent=2)+'\n')


if __name__ == '__main__': main()
