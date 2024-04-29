from jenkinsapi.jenkins import Jenkins
import requests

# pip install jenkinsapi chardet urllib3


def get_server_instance():
    jenkins_url = ""
    server = Jenkins(jenkins_url, username="admin", password="")
    return server


def delete_failed_builds(server):
    skipBranch = [
        "some-branch",
    ]
    try:
        for job_name, job_instance in server.get_jobs():
            print(f"Checking job: {job_name}")
            builds = job_instance.get_build_dict()
            failed_builds_deleted = False
            for build_number in list(builds.keys()):
                build = job_instance.get_build(build_number)
                if build.get_status() == "FAILURE":
                    print(f"Deleting failed build: {job_instance.name} #{build_number}")
                    job_instance.delete_build(build_number)
                    print(f"Deleted build {build_number} from job {job_name}")
                    failed_builds_deleted = True
            if job_name in skipBranch:
                print(f"Skipping job: {job_name}")
                continue
            if failed_builds_deleted:
                print(f"Triggering job: {job_name}")
                job_instance.invoke()
                print(f"Triggered job: {job_name}")

    except requests.exceptions.HTTPError as err:
        print(f"HTTP error occurred: {err}")
    except Exception as e:
        print(f"An error occurred: {e}")


def main():
    try:
        server = get_server_instance()
        delete_failed_builds(server)
    except Exception as e:
        print(f"Failed to connect or authenticate with Jenkins: {e}")


if __name__ == "__main__":
    main()
