docker run -d -e POSTGRES_USER=odoo -e POSTGRES_PASSWORD=odoo -e POSTGRES_DB=postgres --name doob postgres:15
docker run -p 8012:8069 --name odoo -d --link doob:doob -t odoo
