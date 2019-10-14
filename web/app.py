from flask import Flask, abort, jsonify, request

app = Flask(__name__)


@app.route('/', methods=['POST'])
def root():
    url = request.args.getlist('products[]')
    if not url:
        return abort(400)

    return jsonify({})
