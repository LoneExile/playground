import jenkins

JENKINS_URL = ""
JENKINS_USER = ""
JENKINS_TOKEN = ""

ORGANIZATION_NAME = ""
BRANCH_NAME = ""

server = jenkins.Jenkins(JENKINS_URL, username=JENKINS_USER, password=JENKINS_TOKEN)

jobs = server.get_jobs(folder_depth=2)

for job in jobs:
    job_name = job["fullname"]
    print(job_name)
    if ORGANIZATION_NAME in job_name:
        job_config = server.get_job_config(job_name)

        if BRANCH_NAME in job_config:
            server.build_job(job_name)
            print(f"Triggered build for job: {job_name}")
