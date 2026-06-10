"""Convenience launcher for the Flask backend."""

from app import app, init_database


def main():
    init_database()
    app.run(debug=False, host="127.0.0.1", port=5000, threaded=True)


if __name__ == "__main__":
    main()
