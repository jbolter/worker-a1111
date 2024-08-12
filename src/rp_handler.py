import time
import runpod
import requests
from requests.adapters import HTTPAdapter, Retry

LOCAL_URL = "http://127.0.0.1:3000"
TIMEOUT = 600

automatic_session = requests.Session()
retries = Retry(total=10, backoff_factor=0.1, status_forcelist=[502, 503, 504])
automatic_session.mount('http://', HTTPAdapter(max_retries=retries))


# ---------------------------------------------------------------------------- #
#                              Automatic Functions                             #
# ---------------------------------------------------------------------------- #
def wait_for_service(url):
    """
    Check if the service is ready to receive requests.
    """
    retries = 0

    while True:
        try:
            requests.get(url, timeout=120)
            return
        except requests.exceptions.RequestException:
            retries += 1

            # Only log every 15 retries so the logs don't get spammed
            if retries % 15 == 0:
                print("Service not ready yet. Retrying...")
        except Exception as err:
            print("Error: ", err)

        time.sleep(0.2)


def run_inference(inference_request):
    """
    Run inference on a request.
    """
    response = automatic_session.post(url=f'{LOCAL_URL}/sdapi/v1/txt2img',
                                      json=inference_request, timeout=TIMEOUT)
    # return response.json()
    return response

def send_get_request(endpoint):
    return automatic_session.get(url=f"{LOCAL_URL}/{endpoint}", timeout=TIMEOUT)


def send_post_request(endpoint, payload):
    return automatic_session.post(url=f"{LOCAL_URL}/{endpoint}", json=payload, timeout=TIMEOUT)


# ---------------------------------------------------------------------------- #
#                                RunPod Handler                                #
# ---------------------------------------------------------------------------- #
def handler(event):
    """
    This is the handler function that will be called by the serverless.
    """

    method = event["input"]["method"]
    endpoint = event["input"]["endpoint"]
    payload = {}
    if "payload" in event["input"]:
        payload = event["input"]["payload"]

    try:
        if method == "GET":
            response = send_get_request(endpoint)
        elif method == "POST":
            response = send_post_request(endpoint, payload)
        else: 
            response = run_inference(event["input"])
    except Exception as e:
        return {"error": str(e)}

    return response.json()


if __name__ == "__main__":
    wait_for_service(url=f'{LOCAL_URL}/sdapi/v1/sd-models')
    print("WebUI API Service is ready. Starting RunPod Serverless...")
    runpod.serverless.start({"handler": handler})
