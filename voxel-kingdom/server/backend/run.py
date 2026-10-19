"""One authority process/event loop, two transports: localhost HTTP and LAN HTTPS."""
import argparse
import asyncio
from datetime import datetime, timedelta, timezone
import ipaddress
import socket
import ssl
import signal
from contextlib import contextmanager
import uvicorn
from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.x509.oid import NameOID
from .config import PRIVATE
from .app import app


def local_certificate():
    key_path, cert_path = PRIVATE / "lan-key.pem", PRIVATE / "lan-cert.pem"
    names = {"127.0.0.1"}
    try:
        names.update(socket.gethostbyname_ex(socket.gethostname())[2])
    except OSError:
        pass
    names = {name for name in names if not name.startswith("169.254")}
    if cert_path.exists() and key_path.exists():
        certificate = x509.load_pem_x509_certificate(cert_path.read_bytes())
        existing = {str(ip) for ip in certificate.extensions.get_extension_for_class(x509.SubjectAlternativeName).value.get_values_for_type(x509.IPAddress)}
        if names <= existing and certificate.not_valid_after_utc > datetime.now(timezone.utc)+timedelta(days=7):
            return cert_path, key_path
    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    subject = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME,"Voxel Kingdom Local Development")])
    now = datetime.now(timezone.utc)
    certificate = (x509.CertificateBuilder().subject_name(subject).issuer_name(subject)
        .public_key(key.public_key()).serial_number(x509.random_serial_number())
        .not_valid_before(now-timedelta(minutes=5)).not_valid_after(now+timedelta(days=365))
        .add_extension(x509.SubjectAlternativeName([x509.DNSName("localhost"),
            *[x509.IPAddress(ipaddress.ip_address(name)) for name in sorted(names)]]),critical=False)
        .add_extension(x509.BasicConstraints(ca=False,path_length=None),critical=True)
        .sign(key,hashes.SHA256()))
    key_path.write_bytes(key.private_bytes(serialization.Encoding.PEM,serialization.PrivateFormat.PKCS8,serialization.NoEncryption()))
    cert_path.write_bytes(certificate.public_bytes(serialization.Encoding.PEM))
    return cert_path,key_path


async def run(args):
    certificate,key=local_certificate()
    configs=[uvicorn.Config(app,host=args.bind,port=args.port,access_log=False,lifespan="off"),
             uvicorn.Config(app,host=args.bind,port=args.tls_port,access_log=False,lifespan="off",
                 ssl_certfile=str(certificate),ssl_keyfile=str(key))]
    class Server(uvicorn.Server):
        @contextmanager
        def capture_signals(self):
            yield
    servers=[Server(config) for config in configs]
    def stop(*_):
        for server in servers:
            server.should_exit = True
    previous={sig:signal.signal(sig,stop) for sig in (signal.SIGINT,signal.SIGTERM)}
    try:
        async with app.router.lifespan_context(app):
            await asyncio.gather(*(server.serve() for server in servers))
    finally:
        for sig,handler in previous.items():
            signal.signal(sig,handler)


if __name__ == "__main__":
    parser=argparse.ArgumentParser()
    parser.add_argument("--bind",default="0.0.0.0")
    parser.add_argument("--port",type=int,default=8765)
    parser.add_argument("--tls-port",type=int,default=8766)
    asyncio.run(run(parser.parse_args()))
